CREATE TABLE public.fleet (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  serial_number text UNIQUE,
  type text,
  make text,
  family text,
  model bigint,
  CONSTRAINT fleet_pkey PRIMARY KEY (id)
);
CREATE TABLE public.inspection (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL UNIQUE,
  created_at timestamp with time zone DEFAULT now(),
  fleet_serial bigint,
  report ARRAY,
  tasks ARRAY,
  customer_id bigint,
  customer_name character varying,
  work_order character varying,
  completed_on timestamp without time zone,
  inspector bigint,
  location character varying,
  asset_id text,
  CONSTRAINT inspection_pkey PRIMARY KEY (id),
  CONSTRAINT Inspection_fleet_serial_fkey FOREIGN KEY (fleet_serial) REFERENCES public.fleet(id)
);
CREATE TABLE public.inventory (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  part_number bigint,
  part_name text,
  component_tag text,
  stock_qty bigint DEFAULT '0'::bigint,
  unit_price bigint,
  fleet_serial bigint,
  CONSTRAINT inventory_pkey PRIMARY KEY (id),
  CONSTRAINT Inventory_fleet_serial_fkey FOREIGN KEY (fleet_serial) REFERENCES public.fleet(id)
);
CREATE TABLE public.order_cart (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  inspection_id bigint,
  parts bigint NOT NULL,
  quantity bigint,
  urgency boolean,
  status character varying DEFAULT '"pending"'::character varying,
  CONSTRAINT order_cart_pkey PRIMARY KEY (id),
  CONSTRAINT Order_Cart_inspection_id_fkey FOREIGN KEY (inspection_id) REFERENCES public.inspection(id),
  CONSTRAINT Order_Cart_parts_fkey FOREIGN KEY (parts) REFERENCES public.parts(id)
);
CREATE TABLE public.parts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  part_name text,
  part_description text,
  serial_number numeric UNIQUE,
  CONSTRAINT parts_pkey PRIMARY KEY (id)
);
CREATE TABLE public.report (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  inspection_id bigint,
  tasks ARRAY,
  report_pdf text,
  pdf_created timestamp without time zone,
  CONSTRAINT report_pkey PRIMARY KEY (id),
  CONSTRAINT Report_inspection_id_fkey FOREIGN KEY (inspection_id) REFERENCES public.inspection(id)
);
CREATE TABLE public.task (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  title character varying,
  state text,
  images ARRAY,
  anomolies ARRAY,
  index integer,
  fleet_serial bigint,
  inspection_id bigint,
  description character varying,
  feedback character varying,
  CONSTRAINT task_pkey PRIMARY KEY (id),
  CONSTRAINT Task_inspection_id_fkey FOREIGN KEY (inspection_id) REFERENCES public.inspection(id)
);
CREATE TABLE public.todo (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  title character varying,
  index integer,
  fleet_serial bigint,
  description character varying,
  CONSTRAINT todo_pkey PRIMARY KEY (id),
  CONSTRAINT Todo_fleet_serial_fkey FOREIGN KEY (fleet_serial) REFERENCES public.fleet(id)
);