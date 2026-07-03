-- Idempotent role creation via SELECT CASE ... \gexec
-- psql interpolates :'var' at the SELECT level, then \gexec executes the result
-- Environment suffix (e.g., staging, prod) passed via -v env=...

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'core_' || :'env')
  THEN format('ALTER ROLE %I LOGIN PASSWORD %L', 'core_' || :'env', :'core_pw')
  ELSE format('CREATE ROLE %I LOGIN PASSWORD %L', 'core_' || :'env', :'core_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shuttleforge_' || :'env')
  THEN format('ALTER ROLE %I LOGIN PASSWORD %L', 'shuttleforge_' || :'env', :'sf_pw')
  ELSE format('CREATE ROLE %I LOGIN PASSWORD %L', 'shuttleforge_' || :'env', :'sf_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'podbay_' || :'env')
  THEN format('ALTER ROLE %I LOGIN PASSWORD %L', 'podbay_' || :'env', :'podbay_pw')
  ELSE format('CREATE ROLE %I LOGIN PASSWORD %L', 'podbay_' || :'env', :'podbay_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nerfherder_' || :'env')
  THEN format('ALTER ROLE %I LOGIN PASSWORD %L', 'nerfherder_' || :'env', :'nf_pw')
  ELSE format('CREATE ROLE %I LOGIN PASSWORD %L', 'nerfherder_' || :'env', :'nf_pw')
END \gexec

-- Idempotent database creation
SELECT format('CREATE DATABASE %I OWNER %I', 'core_' || :'env', 'core_' || :'env')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'core_' || :'env') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'shuttleforge_' || :'env', 'shuttleforge_' || :'env')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'shuttleforge_' || :'env') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'podbay_' || :'env', 'podbay_' || :'env')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'podbay_' || :'env') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', 'nerfherder_' || :'env', 'nerfherder_' || :'env')
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'nerfherder_' || :'env') \gexec
