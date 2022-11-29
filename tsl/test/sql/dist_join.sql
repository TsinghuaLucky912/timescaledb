-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

\c :TEST_DBNAME :ROLE_CLUSTER_SUPERUSER

\set ECHO all

\set DATA_NODE_1 :TEST_DBNAME _1
\set DATA_NODE_2 :TEST_DBNAME _2
\set DATA_NODE_3 :TEST_DBNAME _3

-- Add data nodes
SELECT node_name, database, node_created, database_created, extension_created
FROM (
  SELECT (add_data_node(name, host => 'localhost', DATABASE => name)).*
  FROM (VALUES (:'DATA_NODE_1'), (:'DATA_NODE_2'), (:'DATA_NODE_3')) v(name)
) a;
GRANT USAGE ON FOREIGN SERVER :DATA_NODE_1, :DATA_NODE_2, :DATA_NODE_3 TO PUBLIC;

\des


drop table if exists metric;
create table metric(ts timestamptz, id int, value float);
select create_distributed_hypertable('metric', 'ts', 'id');
insert into metric values ('2022-02-02 02:02:02+03', 1, '50');

-- The reference table
create table metric_name(id int primary key, name text);
insert into metric_name values (1, 'cpu1');

CALL distributed_exec($$create table metric_name(id int primary key, name text);$$);
CALL distributed_exec($$insert into metric_name values (1, 'cpu1');$$);

create table metric_name_local(id int primary key, name text);
insert into metric_name_local values (1, 'cpu1');

create table dummy_table(id int primary key, name text);
CALL distributed_exec($$create table dummy_table(id int primary key, name text);$$);

create table dummy_table_local(id int primary key, name text);

SET client_min_messages TO WARNING;

ALTER FOREIGN DATA WRAPPER timescaledb_fdw OPTIONS (ADD join_reference_tables 'metric_name, dummy_table');

\set ON_ERROR_STOP 0
ALTER FOREIGN DATA WRAPPER timescaledb_fdw OPTIONS (SET join_reference_tables 'metric_name, dummy_table, non_existing_table');
ALTER FOREIGN DATA WRAPPER timescaledb_fdw OPTIONS (SET join_reference_tables 'metric_name, dummy_table, metric');
\set ON_ERROR_STOP 1

ALTER FOREIGN DATA WRAPPER timescaledb_fdw OPTIONS (SET join_reference_tables 'metric_name, dummy_table');

SET client_min_messages TO DEBUG1;

explain (verbose, analyze, costs off, timing off, summary off)
select name, value from metric 
left join metric_name using (id)
where name like 'cpu%'
and ts between '2022-02-02 02:02:02+03' and '2022-02-02 02:12:02+03';

-- Join with reference table
explain (verbose, analyze, costs off, timing off, summary off)
select name, max(value) from metric 
left join metric_name using (id)
where name like 'cpu%'
and ts between '2022-02-02 02:02:02+03' and '2022-02-02 02:12:02+03'
group by name;

-- Join with reference table
explain (verbose, analyze, costs off, timing off, summary off)
select name, max(value) from metric, metric_name
where metric.id = metric_name.id
and name like 'cpu%'
and ts between '2022-02-02 02:02:02+03' and '2022-02-02 02:12:02+03'
group by name;

-- Join with local table
explain (verbose, analyze, costs off, timing off, summary off)
select name, max(value) from metric 
left join metric_name_local using (id)
where name like 'cpu%'
and ts between '2022-02-02 02:02:02+03' and '2022-02-02 02:12:02+03'
group by name;

-- Join with local table
explain (verbose, analyze, costs off, timing off, summary off)
select name, max(value) from metric, metric_name_local
where metric.id = metric_name_local.id
and name like 'cpu%'
and ts between '2022-02-02 02:02:02+03' and '2022-02-02 02:12:02+03'
group by name;

-- Tests with aliases 
