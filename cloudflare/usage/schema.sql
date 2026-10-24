-- How often each club's forecast and each lake's view was loaded, per day (UTC).
-- Nothing about who loaded it is stored.
CREATE TABLE IF NOT EXISTS hits (
  day TEXT NOT NULL,
  kind TEXT NOT NULL,  -- 'club' or 'lake'
  id TEXT NOT NULL,
  n INTEGER NOT NULL,
  PRIMARY KEY (day, kind, id)
);

-- Calls the backend's jobs made to outside services, per day (UTC), as the services count them.
CREATE TABLE IF NOT EXISTS budget (
  day TEXT NOT NULL,
  service TEXT NOT NULL,  -- 'open-meteo', 'copernicus'
  job TEXT NOT NULL,
  calls REAL NOT NULL,
  PRIMARY KEY (day, service, job)
);
