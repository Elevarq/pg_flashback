EXTENSION = pg_flashback
DATA = pg_flashback--1.0.sql
MODULES = pg_flashback

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
