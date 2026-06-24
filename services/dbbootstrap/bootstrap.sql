-- Idempotent role creation via SELECT CASE ... \gexec
-- psql interpolates :'var' at the SELECT level, then \gexec executes the result

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'core_staging')
  THEN format('ALTER ROLE core_staging LOGIN PASSWORD %L', :'core_pw')
  ELSE format('CREATE ROLE core_staging LOGIN PASSWORD %L', :'core_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'shuttleforge_staging')
  THEN format('ALTER ROLE shuttleforge_staging LOGIN PASSWORD %L', :'sf_pw')
  ELSE format('CREATE ROLE shuttleforge_staging LOGIN PASSWORD %L', :'sf_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'podbay_staging')
  THEN format('ALTER ROLE podbay_staging LOGIN PASSWORD %L', :'podbay_pw')
  ELSE format('CREATE ROLE podbay_staging LOGIN PASSWORD %L', :'podbay_pw')
END \gexec

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nerfherder_staging')
  THEN format('ALTER ROLE nerfherder_staging LOGIN PASSWORD %L', :'nf_pw')
  ELSE format('CREATE ROLE nerfherder_staging LOGIN PASSWORD %L', :'nf_pw')
END \gexec

-- Idempotent database creation
SELECT 'CREATE DATABASE core_staging OWNER core_staging'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'core_staging') \gexec
SELECT 'CREATE DATABASE shuttleforge_staging OWNER shuttleforge_staging'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'shuttleforge_staging') \gexec
SELECT 'CREATE DATABASE podbay_staging OWNER podbay_staging'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'podbay_staging') \gexec
SELECT 'CREATE DATABASE nerfherder_staging OWNER nerfherder_staging'
  WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'nerfherder_staging') \gexec
