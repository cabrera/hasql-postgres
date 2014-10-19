module Hasql.Postgres.OID where

import Database.PostgreSQL.LibPQ (Oid(..))


type OID = Oid

abstime     = Oid 702
bit         = Oid 1560
bool        = Oid 16
box         = Oid 603
bpchar      = Oid 1042
bytea       = Oid 17
char        = Oid 18
cid         = Oid 29
cidr        = Oid 650
circle      = Oid 718
date        = Oid 1082
float4      = Oid 700
float8      = Oid 701
inet        = Oid 869
int2        = Oid 21
int4        = Oid 23
int8        = Oid 20
interval    = Oid 1186
json        = Oid 114
line        = Oid 628
lseg        = Oid 601
macaddr     = Oid 829
money       = Oid 790
name        = Oid 19
numeric     = Oid 1700
oid         = Oid 26
path        = Oid 602
point       = Oid 600
polygon     = Oid 604
record      = Oid 2249
refcursor   = Oid 1790
regproc     = Oid 24
reltime     = Oid 703
text        = Oid 25
tid         = Oid 27
time        = Oid 1083
timestamp   = Oid 1114
timestamptz = Oid 1184
timetz      = Oid 1266
tinterval   = Oid 704
unknown     = Oid 705
uuid        = Oid 2950
varbit      = Oid 1562
varchar     = Oid 1043
void        = Oid 2278
xid         = Oid 28
xml         = Oid 142