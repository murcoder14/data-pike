CREATE TABLE IF NOT EXISTS weather_db.temperature (
  yyyy_mm_dd string,
  city_temps map<string,double>
  )
LOCATION 's3://weather-data-output-dev/weather_db/temperature/'
TBLPROPERTIES ( 
  'table_type' = 'ICEBERG',
  'format' = 'Avro',
  'write_compression'= 'zstd'
);

INSERT INTO weather_db.temperature (yyyy_mm_dd, city_temps)
VALUES
  ('2026-01-05', MAP(ARRAY['Mumbai', 'Sydney'],    ARRAY[78.5, 70.3])),
  ('2026-01-06', MAP(ARRAY['Tokyo', 'Auckland'],    ARRAY[37.1, 81.8])),
  ('2026-01-07', MAP(ARRAY['Dubai', 'Seoul'],    ARRAY[88.4, 48.1]));

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE weather_db.customers (
  customer_id  BIGINT,
  name         string,
  address      STRUCT<street:string,city:string,state:string,zip:string,country:string>
 )
LOCATION 's3://weather-data-output-dev/weather_db/customers/'
TBLPROPERTIES (
  'table_type' = 'ICEBERG',
  'format' = 'Avro',
  'write_compression'= 'zstd'
);

INSERT INTO weather_db.customers (customer_id, name, address)
VALUES
  (1, 'Alice Johnson', ROW('123 Main St',   'Boston',      'MA', '02101', 'USA')),
  (2, 'Bob Smith',     ROW('456 Oak Ave',   'Los Angeles', 'CA', '90001', 'USA')),
  (3, 'Carol White',   ROW('789 Pine Rd',   'Chicago',     'IL', '60601', 'USA'));

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE members (
  member_id    bigint,
  member_name  string,
  insurance    struct<
    carrier    : string,
    policy_no   : string,
    coverage : struct<plan_type:string,deductible: double,copay: double>,
    primary_care : struct<doctor_nm:string,phone:string>
  >
)
LOCATION 's3://weather-data-output-dev/weather_db/members/'
TBLPROPERTIES (
  'table_type' = 'ICEBERG',
  'format' = 'Avro',
  'write_compression'= 'zstd'
);

INSERT INTO weather_db.members
VALUES
  (1,'Alice Johnson',ROW('Blue Cross','BC-100234',ROW('PPO', 1500.00, 25.00),ROW('Dr. Sarah Smith', '617-555-0101'))),
  (2,'Bob Martinez',ROW('Aetna','AE-299871',ROW('HMO', 2000.00, 40.00),ROW('Dr. Mark Wood', '312-555-0188'))),
  (3,'Carol White',ROW( 'United Health','UH-874321',ROW('HDHP', 3000.00, 0.00),ROW('Dr. Laura Wilson', '213-555-0145')));

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS weather_db.products (
  product_id  bigint,
  name        string,
  tags        array<string>,
  reviews     array<struct<
    reviewer    : string,
    rating      : int,
    comment     : string,
    review_date : date
  >>,
  variants    array<array<string>>
)
LOCATION 's3://weather-data-output-dev/weather_db/products/'
TBLPROPERTIES (
  'table_type' = 'ICEBERG',
  'format' = 'Avro',
  'write_compression'= 'zstd'
);

INSERT INTO weather_db.products VALUES (
  101,
  'Mechanical Keyboard',
  ARRAY['electronics', 'peripherals', 'gaming'],
  ARRAY[
    ROW('alice', 5, 'Fantastic tactile feel!', DATE '2026-05-10'),
    ROW('bob',   4, 'Good but loud',          DATE '2026-05-07')
  ],
  ARRAY[
    ARRAY['Black', 'US Layout'],
    ARRAY['White', 'UK Layout']
  ]
);

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

DROP TABLE weather_db.temperature;
DROP TABLE weather_db.customers;
DROP TABLE weather_db.members;
DROP TABLE weather_db.products;
