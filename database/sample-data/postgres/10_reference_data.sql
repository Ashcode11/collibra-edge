-- Reference data (idempotent upserts). Run as bank_migrator.
\set ON_ERROR_STOP on
SET ROLE bank_owner;

INSERT INTO reference.currencies (currency_code, currency_name, minor_units) VALUES
  ('GBP','Pound Sterling',2), ('EUR','Euro',2), ('USD','US Dollar',2),
  ('JPY','Japanese Yen',0), ('CHF','Swiss Franc',2), ('SGD','Singapore Dollar',2)
ON CONFLICT (currency_code) DO UPDATE SET currency_name = EXCLUDED.currency_name, minor_units = EXCLUDED.minor_units;

-- is_high_risk is ILLUSTRATIVE ONLY for AML demos; it is not an official list.
INSERT INTO reference.countries (country_code, country_name, is_eea, is_high_risk) VALUES
  ('GB','United Kingdom',false,false), ('IE','Ireland',true,false), ('FR','France',true,false),
  ('DE','Germany',true,false), ('NL','Netherlands',true,false), ('ES','Spain',true,false),
  ('IT','Italy',true,false), ('PL','Poland',true,false), ('US','United States',false,false),
  ('JP','Japan',false,false), ('SG','Singapore',false,false), ('IN','India',false,false),
  ('AE','United Arab Emirates',false,false), ('CH','Switzerland',false,false),
  ('XA','Synthetic High-Risk Jurisdiction A',false,true), ('XB','Synthetic High-Risk Jurisdiction B',false,true)
ON CONFLICT (country_code) DO UPDATE SET country_name = EXCLUDED.country_name, is_eea = EXCLUDED.is_eea, is_high_risk = EXCLUDED.is_high_risk;

INSERT INTO reference.branches (branch_code, branch_name, city, country_code, sort_code) VALUES
  ('LDN001','London City','London','GB','990001'), ('LDN002','Canary Wharf','London','GB','990002'),
  ('MAN001','Manchester Spinningfields','Manchester','GB','990003'), ('BHM001','Birmingham Colmore Row','Birmingham','GB','990004'),
  ('EDI001','Edinburgh St Andrew Square','Edinburgh','GB','990005'), ('GLA001','Glasgow Buchanan Street','Glasgow','GB','990006'),
  ('LDS001','Leeds Park Row','Leeds','GB','990007'), ('BRS001','Bristol Corn Street','Bristol','GB','990008'),
  ('CDF001','Cardiff Queen Street','Cardiff','GB','990009'), ('BEL001','Belfast Donegall Place','Belfast','GB','990010'),
  ('DIG001','Digital Bank','London','GB','990011'), ('CORP01','Corporate Banking','London','GB','990012')
ON CONFLICT (branch_code) DO NOTHING;   -- sort codes 99xxxx are not allocated to real banks in this lab

INSERT INTO reference.products (product_code, product_name, product_type, customer_type, interest_rate) VALUES
  ('CA01','Everyday Current Account','CURRENT','INDIVIDUAL',0.000),
  ('CA02','Premier Current Account','CURRENT','INDIVIDUAL',0.500),
  ('SA01','Instant Access Saver','SAVINGS','INDIVIDUAL',3.250),
  ('SA02','1-Year Fixed Saver','SAVINGS','INDIVIDUAL',4.100),
  ('LN01','Personal Loan','LOAN','INDIVIDUAL',7.900),
  ('CC01','Rewards Credit Card','CARD','INDIVIDUAL',24.900),
  ('BC01','Business Current Account','CURRENT','BUSINESS',0.000),
  ('BS01','Business Deposit Account','SAVINGS','BUSINESS',2.750)
ON CONFLICT (product_code) DO UPDATE SET product_name = EXCLUDED.product_name, interest_rate = EXCLUDED.interest_rate;
