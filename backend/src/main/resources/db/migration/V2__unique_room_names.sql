CREATE UNIQUE INDEX uq_rooms_name_ci ON rooms (lower(btrim(name)));
