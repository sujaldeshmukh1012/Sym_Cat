-- INVENTORY: Parts/items with part number, brand, quantity
CREATE TABLE inventory (
    id          SERIAL PRIMARY KEY,
    user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    part_number VARCHAR(100) NOT NULL UNIQUE,
    brand       VARCHAR(150),
    quantity    INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- MACHINE SPECS: Machine details, defects, and parts changed
CREATE TABLE machine_specs (
    id            SERIAL PRIMARY KEY,
    user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name          VARCHAR(255) NOT NULL,
    Location      VARCHAR(255),
    usecase       TEXT,
    details       TEXT,
    defect_parts  TEXT[],                  -- array of defective part names/IDs
    parts_changed TEXT[],                  -- array of parts that were changed
    changed_at    TIMESTAMPTZ,             -- date & time of parts change
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- LOGS: Inspection logs tied to a machine
CREATE TABLE logs (
    id              SERIAL PRIMARY KEY,
    user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    machine_spec_id INTEGER REFERENCES machine_specs(id) ON DELETE SET NULL,
    inspected_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- when inspection was done
    status          VARCHAR(50) NOT NULL CHECK (status IN ('Low', 'Moderate', 'Critical')),
    problem         TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- REPORTS: Generated reports stored in Supabase Storage
CREATE TABLE reports (
    id          SERIAL PRIMARY KEY,
    user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    public_url  TEXT NOT NULL,             -- bucket public URL
    created_at  TIMESTAMPTZ DEFAULT NOW()
);


-- RLS (Row Level Security) — enable per table so users only see their own data
ALTER TABLE inventory     ENABLE ROW LEVEL SECURITY;
ALTER TABLE machine_specs ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports       ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own inventory"     ON inventory     FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users manage own machine_specs" ON machine_specs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users manage own logs"          ON logs          FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Users manage own reports"       ON reports       FOR ALL USING (auth.uid() = user_id);