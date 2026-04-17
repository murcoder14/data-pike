# networking/main.tf — Line-by-Line Walkthrough

---

### Lines 1–4: Comments

```hcl
# Networking Module - VPC, Subnets, Security Groups, VPC Endpoints
#
# Provisions a VPC with private subnets across multiple AZs,
# security groups for Flink, route tables, and VPC endpoints.
```

This module creates the isolated private network that the Flink application runs inside.

---

### Lines 10–12: Data Source — Availability Zones

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}
```

Looks up which availability zones (AZs) are available in the current region. AZs are physically separate data centers within a region (e.g., `us-east-1a`, `us-east-1b`). The `state = "available"` filter excludes any AZs that are down or restricted. This list is used later to place subnets in different AZs.

---

### Lines 14–22: VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}
```

- `cidr_block = var.vpc_cidr` — The IP address range for the entire network. Default is `10.0.0.0/16`, which gives you 65,536 IP addresses. Think of this as defining the size of your private network.
- `enable_dns_support = true` — Turns on the VPC's built-in DNS resolver (at the `.2` address of the CIDR, e.g., `10.0.0.2`). Without this, services inside the VPC can't resolve hostnames.
- `enable_dns_hostnames = true` — Assigns DNS hostnames to resources in the VPC. Required for VPC endpoints with `private_dns_enabled` to work — it lets services use standard AWS hostnames (like `kinesis.us-east-1.amazonaws.com`) that resolve to the private endpoint IP instead of the public one.

---

### Lines 28–40: VPC Flow Logs — Log Group (Optional)

```hcl
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/flowlogs/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn
  ...
}
```

- `count = var.enable_vpc_flow_logs ? 1 : 0` — This is a conditional. If `enable_vpc_flow_logs` is `true`, create 1 log group. If `false`, create 0 (skip it entirely). This is how Terraform does "optional resources."
- The rest is the same CloudWatch log group pattern you saw in `monitoring/main.tf`.

---

### Lines 42–65: VPC Flow Logs — IAM Role (Optional)

```hcl
resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name = "${var.project_name}-${var.environment}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  ...
}
```

This is the first IAM role you're seeing in detail. Two concepts:

- `assume_role_policy` — This answers "who is allowed to become this role?" Here, only the `vpc-flow-logs.amazonaws.com` service can assume it. No human, no other service.
- `sts:AssumeRole` — STS (Security Token Service) is how AWS services "put on" a role. The flow logs service calls STS, says "I want to be this role," STS checks the assume role policy, and if allowed, hands back temporary credentials.

### Lines 67–86: VPC Flow Logs — Role Policy (Optional)

```hcl
resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  ...
  policy = jsonencode({
    ...
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.vpc_flow_logs[0].arn,
          "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
        ]
      }
    ]
  })
}
```

- The assume role policy says who can become the role. This policy says what the role can do once assumed.
- It can only write logs (`PutLogEvents`) to the specific flow logs log group — nothing else.
- `[0]` in `vpc_flow_logs[0]` — because we used `count`, the resource is a list. `[0]` gets the first (and only) element.

### Lines 88–101: VPC Flow Log Resource (Optional)

```hcl
resource "aws_flow_log" "vpc" {
  count                = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  ...
}
```

- `traffic_type = "ALL"` — Records both accepted and rejected traffic. You could set this to `"ACCEPT"` or `"REJECT"` only, but `"ALL"` gives the full picture for security auditing.
- `iam_role_arn` — The role the flow log service assumes to write logs.
- `log_destination` — Where the logs go (the CloudWatch log group).

All four flow log resources use the same `count` conditional, so they're all created or all skipped together.

---

### Lines 103–113: Private Subnets

```hcl
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.environment}-${data.aws_availability_zones.available.names[count.index]}"
    Tier = "private"
  }
}
```

- `count = 2` — Creates two subnets. Terraform runs this block twice, with `count.index` being `0` and `1`.
- `cidrsubnet(var.vpc_cidr, 8, count.index)` — Carves the VPC's IP range into smaller chunks. With a `/16` VPC:
  - Index 0 → `10.0.0.0/24` (256 IPs)
  - Index 1 → `10.0.1.0/24` (256 IPs)
  - The `8` means "add 8 bits to the prefix" (16 + 8 = 24).
- `availability_zone` — Puts subnet 0 in the first AZ (e.g., `us-east-1a`) and subnet 1 in the second (e.g., `us-east-1b`). This gives high availability — if one data center goes down, the other subnet keeps running.
- `Tier = "private"` — A custom tag. These subnets have no internet gateway, so they're truly private.

---

### Lines 118–137: Security Groups

```hcl
resource "aws_security_group" "flink" {
  name_prefix = "${var.project_name}-${var.environment}-"
  description = "Security group for the Flink application"
  vpc_id      = aws_vpc.main.id
  ...
}

resource "aws_security_group" "endpoints" {
  name_prefix = "${var.project_name}-${var.environment}-endpoints-"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id
  ...
}
```

Two security groups (firewalls):
- `flink` — Controls what the Flink application can talk to.
- `endpoints` — Controls what can talk to the VPC endpoints.

`name_prefix` instead of `name` — AWS appends a random suffix. This avoids naming conflicts if Terraform needs to recreate the security group (create new one before deleting old one).

By default, security groups deny all inbound traffic and allow all outbound. But the rules below override the outbound defaults with specific allow rules, effectively making it "deny all, allow specific."

---

### Lines 139–141: S3 Prefix List Data Source

```hcl
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.aws_region}.s3"
}
```

A prefix list is an AWS-managed list of IP ranges for a service. S3's IP addresses change frequently, so instead of hardcoding IPs, you reference this list. AWS keeps it updated automatically. Used in the security group rule below.

---

### Lines 143–167: Flink Security Group Egress Rules

Four outbound rules — this is everything Flink is allowed to send traffic to:

#### DNS over UDP (lines 143–149)

```hcl
resource "aws_vpc_security_group_egress_rule" "flink_dns_udp" {
  security_group_id = aws_security_group.flink.id
  description       = "Allow outbound DNS to VPC resolver over UDP"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
}
```

- Port 53 UDP to the VPC DNS resolver. `cidrhost(var.vpc_cidr, 2)` calculates the resolver's IP — AWS always puts it at the `.2` address (e.g., `10.0.0.2`).
- `/32` means exactly one IP address.
- Without DNS, Flink can't resolve hostnames like `kinesis.us-east-1.amazonaws.com`.

#### DNS over TCP (lines 151–157)

```hcl
resource "aws_vpc_security_group_egress_rule" "flink_dns_tcp" {
  ...
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
}
```

Same as above but TCP. DNS normally uses UDP, but falls back to TCP for large responses (over 512 bytes). Both are needed.

#### HTTPS to S3 (lines 159–165)

```hcl
resource "aws_vpc_security_group_egress_rule" "flink_s3_https" {
  ...
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_prefix_list.s3.id
}
```

- Port 443 (HTTPS) to S3's IP ranges via the prefix list. This is for the S3 gateway endpoint — gateway endpoints use IP routing, so the security group needs to allow traffic to S3's IPs.

#### HTTPS to Interface Endpoints (lines 167–173)

```hcl
resource "aws_vpc_security_group_egress_rule" "flink_endpoints_https" {
  ...
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}
```

- Port 443 to anything in the `endpoints` security group. This covers all the interface endpoints (Kinesis, Glue, KMS, CloudWatch Logs, STS).
- `referenced_security_group_id` — Instead of specifying IP addresses, this says "allow traffic to any resource that has the endpoints security group attached." This is more maintainable than hardcoding IPs.

---

### Lines 175–186: Endpoints Ingress Rule

```hcl
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_flink" {
  security_group_id            = aws_security_group.endpoints.id
  ...
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.flink.id
  ...
}
```

The other side of the conversation. The Flink egress rule says "Flink can send HTTPS to endpoints." This ingress rule says "endpoints accept HTTPS from Flink." Both rules must exist for traffic to flow — security groups are stateful but you still need rules in both directions for the initial connection.

---

### Lines 191–205: Route Table

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  ...
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

- A route table defines where network traffic goes. This one has no routes to an internet gateway — so there's no path to the internet.
- `aws_route_table_association` — Links both private subnets to this route table. `length(aws_subnet.private)` returns `2`, so it creates two associations.
- The S3 gateway endpoint (below) automatically adds a route to this table for S3 traffic.

---

### Lines 211–222: S3 Gateway Endpoint

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  ...
}
```

- `vpc_endpoint_type = "Gateway"` — Gateway endpoints work at the routing level. AWS adds a route to the route table that directs S3-bound traffic through the endpoint instead of the internet. Free of charge.
- `route_table_ids` — Which route tables get the S3 route. Our private subnets use this route table, so they can reach S3.

#### Why Each VPC Endpoint Is Required

Since the Flink app runs in private subnets with no internet access, it can't reach any AWS service through the public internet. Every AWS service it needs to talk to requires a VPC endpoint — a private tunnel from the VPC directly to that service:

- `aws_vpc_endpoint "s3"` — Flink reads input files from the Input Bucket, writes results to the Iceberg Bucket, and loads its own code from the JAR Bucket. All three are S3. Without this endpoint, Flink can't access any file storage. This is a Gateway endpoint (free), because S3 and DynamoDB are the only services that support the gateway type.

- `aws_vpc_endpoint "kinesis"` — Flink consumes file notifications from the Kinesis Data Stream. This is how it knows a new file was uploaded. Without this endpoint, Flink would never receive any notifications and the pipeline would sit idle.

- `aws_vpc_endpoint "glue"` — Flink reads and updates Iceberg table metadata in the Glue Catalog. When it writes new data files to S3, it also updates the Glue table to register those files (schema, partitions, snapshot pointers). Without this endpoint, Flink could write data to S3 but no query engine (like Athena) would know the data exists.

- `aws_vpc_endpoint "kms"` — The S3 buckets and Kinesis stream are encrypted with the CMK. Every time Flink reads encrypted data, the AWS SDK calls KMS to decrypt it. Every time it writes, KMS generates a data key. Without this endpoint, Flink can't decrypt or encrypt anything — all reads and writes to encrypted resources would fail.

- `aws_vpc_endpoint "logs"` — Flink writes application logs to CloudWatch. Without this endpoint, you'd have no visibility into what the app is doing — no error messages, no processing metrics, no debugging information.

- `aws_vpc_endpoint "sts"` — STS (Security Token Service) is how the AWS SDK authenticates. When Flink starts, the SDK calls STS to assume the execution IAM role and get temporary credentials. Those credentials expire and get refreshed periodically, which requires calling STS again. Without this endpoint, Flink can't authenticate at all — it wouldn't be able to call any AWS service, even if all the other endpoints existed.

The dependency chain is roughly:

```
STS (authenticate) → must work first, or nothing else can
KMS (decrypt)      → must work, or encrypted data is unreadable
S3 (files)         → read input, write output, load code
Kinesis (events)   → receive file notifications
Glue (metadata)    → register output data in the catalog
Logs (monitoring)  → write application logs
```

Remove any one and a specific capability breaks. Remove STS and everything breaks.

---

### Lines 226–280: Interface Endpoints (Kinesis, Logs, Glue, KMS, STS)

All five follow the same pattern. Here's Kinesis as the example:

```hcl
resource "aws_vpc_endpoint" "kinesis" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  ...
}
```

- `vpc_endpoint_type = "Interface"` — Interface endpoints create an ENI (elastic network interface — a virtual network card) in each subnet. Traffic goes to the ENI's private IP instead of the public internet. These cost ~$0.01/hour per AZ.
- `subnet_ids = aws_subnet.private[*].id` — The `[*]` is a splat expression. It means "get the `.id` from every subnet in the list." Places an ENI in both subnets for high availability.
- `security_group_ids` — Attaches the endpoints security group, which only allows HTTPS from the Flink security group.
- `private_dns_enabled = true` — This is the magic. It makes `kinesis.us-east-1.amazonaws.com` resolve to the endpoint's private IP instead of the public IP. The Flink app's code doesn't need to know about endpoints — it uses the standard AWS SDK hostname and the DNS resolution handles the routing privately.

The other four endpoints (Logs, Glue, KMS, STS) are identical in structure, just with different `service_name` values:
- `com.amazonaws.{region}.logs` — CloudWatch Logs
- `com.amazonaws.{region}.glue` — Glue Catalog
- `com.amazonaws.{region}.kms` — KMS encryption
- `com.amazonaws.{region}.sts` — Security Token Service (for IAM role assumption)

---

### Summary

This module creates:
- 1 VPC with DNS support
- 2 private subnets in different AZs
- 2 security groups (Flink + endpoints) with 5 tightly scoped rules
- 1 route table linking the subnets
- 6 VPC endpoints (1 gateway for S3, 5 interface for Kinesis/Logs/Glue/KMS/STS)
- Optionally: VPC flow logs (log group + IAM role + flow log resource)

The key takeaway: the Flink app has zero internet access. It can only reach AWS services through VPC endpoints, and only the specific services it needs. The security groups enforce this at the network level, independent of IAM policies.

---

## Q&A

### Q: The flow logs log group uses `kms_key_id = var.cloudwatch_log_kms_key_arn` — why can't it directly reuse the KMS key created in storage/main.tf?

It actually does reuse the same KMS key from `storage/main.tf`. The root module (`terraform/main.tf`) wires them together:

```hcl
module "networking" {
  source                     = "./modules/networking"
  ...
  cloudwatch_log_kms_key_arn = var.enable_cloudwatch_logs_kms ? module.storage.kms_key_arn : null
}
```

The `cloudwatch_log_kms_key_arn` variable passed into the networking module is `module.storage.kms_key_arn` — that's the CMK created in `storage/main.tf`. It's passed as a variable rather than referenced directly because Terraform modules are isolated — a module can't reach into another module's resources. They communicate through inputs (variables) and outputs.

This is also why the KMS key policy in `storage/main.tf` has the `AllowCloudWatchLogsUse` statement — without it, CloudWatch wouldn't have permission to use the key, and this log group's encryption would fail.

The conditional `var.enable_cloudwatch_logs_kms ? ... : null` means:
- If KMS encryption for logs is enabled → pass the CMK ARN → logs are encrypted with the CMK
- If disabled → pass `null` → CloudWatch uses its default encryption (free, but less control)

The design is: one CMK for the whole project, shared across modules via variables. Not duplicated, not separate keys.

### Q: What do the four flow log resources accomplish collectively?

These four resources work together to answer one question: "What network traffic is flowing through our VPC?"

Here's how they chain together:

1. `aws_flow_log "vpc"` — The recorder. It tells AWS "watch all traffic in this VPC and record it." But it needs two things: somewhere to write the logs, and permission to write them.

2. `aws_cloudwatch_log_group "vpc_flow_logs"` — The destination. This is where the recorded traffic data gets stored. Without it, the flow log has nowhere to write.

3. `aws_iam_role "vpc_flow_logs"` — The identity. AWS's flow log service needs an IAM role to act as, because no AWS service can do anything without an identity. The `assume_role_policy` says "only the `vpc-flow-logs.amazonaws.com` service can use this role."

4. `aws_iam_role_policy "vpc_flow_logs"` — The permission. Once the flow log service assumes the role, this policy says what it can do — specifically, write log entries to that one CloudWatch log group and nothing else.

The flow:

```
VPC traffic occurs
    → aws_flow_log captures it
    → assumes aws_iam_role to get credentials
    → aws_iam_role_policy allows writing to CloudWatch
    → logs land in aws_cloudwatch_log_group
```

Remove any one of the four and the whole thing breaks:
- No log group → nowhere to write
- No role → no identity to authenticate as
- No policy → identity exists but has no permissions
- No flow log → nothing is recording traffic

This pattern (resource + destination + role + policy) repeats throughout AWS whenever a service needs to write to another service. You'll see the same pattern in `kinesis/main.tf` where EventBridge needs to write to Kinesis.


### Q: What does the Resource array with two ARNs mean in the flow logs policy?

Two ARNs are listed because CloudWatch has a two-level hierarchy:

- `aws_cloudwatch_log_group.vpc_flow_logs[0].arn` — This is the log group itself. Needed for actions like `DescribeLogGroups` and `DescribeLogStreams` that operate on the group level.

- `"${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"` — This is everything inside the log group (log streams and their log events). The `:*` suffix is a wildcard that covers all child resources. Needed for actions like `CreateLogStream` and `PutLogEvents` that operate on streams within the group.

If you only had the first one, the role could describe the log group but couldn't write any log entries into it. If you only had the second one, the role could write entries but couldn't discover or describe the group itself.

Together they say: "you can interact with this specific log group and everything inside it, but nothing else."

### Q: What does index zero (`[0]`) mean? Do we have many flow log groups?

No, there's only one. The `[0]` is a side effect of using `count`.

When you add `count` to a resource, Terraform treats it as a list — even if `count = 1`. So instead of `aws_cloudwatch_log_group.vpc_flow_logs` being a single object, it becomes a list with one element: `aws_cloudwatch_log_group.vpc_flow_logs[0]`.

It's like declaring an array of size 1 in code. You still need `array[0]` to access the element, even though there's only one.

The reason `count` is used here at all is for the conditional:

```hcl
count = var.enable_vpc_flow_logs ? 1 : 0
```

- `true` → `count = 1` → list with one element → access via `[0]`
- `false` → `count = 0` → empty list → resource doesn't exist

There's no way to have 2 or more flow log groups here. The `count` is only being used as an on/off switch, not to create multiple instances. The `[0]` is just the syntax tax you pay for that pattern.


### Q: What do the four Flink egress security group rules collectively allow?

These four rules are the complete list of outbound traffic the Flink application is allowed to send. Nothing else can leave. Together they allow exactly three things:

1. DNS lookups (`flink_dns_udp` + `flink_dns_tcp`) — Flink can ask the VPC's DNS resolver "what IP address is `kinesis.us-east-1.amazonaws.com`?" over both UDP and TCP on port 53, but only to the single IP of the VPC resolver (`10.0.0.2`). Without DNS, Flink can't find any service.

2. HTTPS to S3 (`flink_s3_https`) — Flink can send HTTPS traffic (port 443) to S3's IP ranges. This goes through the S3 gateway endpoint. Needed to read input files, write Iceberg results, and load the JAR.

3. HTTPS to interface endpoints (`flink_endpoints_https`) — Flink can send HTTPS traffic (port 443) to anything in the endpoints security group. That covers Kinesis, Glue, KMS, CloudWatch Logs, and STS. Needed to consume stream records, update table metadata, decrypt data, write logs, and assume IAM roles.

What's notably absent:
- No rule allowing traffic to `0.0.0.0/0` (the internet)
- No rule for any port other than 53 and 443
- No rule for any protocol other than UDP (DNS only) and TCP
- No rule allowing traffic to any IP outside the VPC DNS resolver, S3 prefix list, or endpoints security group

So the Flink app can resolve hostnames, talk to S3, and talk to five specific AWS services — and literally nothing else at the network level.
