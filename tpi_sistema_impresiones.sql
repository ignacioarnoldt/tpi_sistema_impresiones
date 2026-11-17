-- =====================================================================
--  TPI - BASE DE DATOS I - UTN Villa María
--  Sistema de gestión de pedidos de impresión
--  Profesora: Ivana Garabello
--  Alumnos: Ignacio Arnoldt, Benjamín Giorgis, Martín Peralta, Nicolás Vasone
--
--  Orden del script:
--    1) Creación de la base de datos
--    2) Tablas
--    3) Tablas de datos del negocio
--    4) Datos de prueba
--    5) Vistas (estado del pedido y total calculado)
--    6) Triggers (reglas de negocio que el modelo no puede expresar solo)
--    7) Consultas de demostración
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) BASE DE DATOS
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS sistema_impresiones;
CREATE DATABASE sistema_impresiones
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE sistema_impresiones;

-- ---------------------------------------------------------------------
-- 2) TABLAS 
-- ---------------------------------------------------------------------

CREATE TABLE localidad (
    id_localidad  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre        VARCHAR(80)  NOT NULL,
    provincia     VARCHAR(60)  NOT NULL DEFAULT 'Córdoba',
    PRIMARY KEY (id_localidad),
    CONSTRAINT uq_localidad UNIQUE (nombre, provincia)
) ENGINE=InnoDB;

CREATE TABLE zona (
    id_zona      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(50)  NOT NULL,
    descripcion  VARCHAR(150) NULL,
    PRIMARY KEY (id_zona),
    CONSTRAINT uq_zona_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE tipo_trabajo (
    id_tipo_trabajo  TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre           VARCHAR(30) NOT NULL,
    PRIMARY KEY (id_tipo_trabajo),
    CONSTRAINT uq_tipo_trabajo_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE tipo_tarea (
    id_tipo_tarea  TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre         VARCHAR(30) NOT NULL,
    orden          TINYINT UNSIGNED NOT NULL,
    PRIMARY KEY (id_tipo_tarea),
    CONSTRAINT uq_tipo_tarea_nombre UNIQUE (nombre),
    CONSTRAINT uq_tipo_tarea_orden  UNIQUE (orden)
) ENGINE=InnoDB;

CREATE TABLE material (
    id_material  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(50)  NOT NULL,
    descripcion  VARCHAR(150) NULL,
    activo       BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_material),
    CONSTRAINT uq_material_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE formato (
    id_formato   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    descripcion  VARCHAR(20)  NOT NULL,
    ancho_cm     DECIMAL(6,2) NULL,
    alto_cm      DECIMAL(6,2) NULL,
    activo       BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_formato),
    CONSTRAINT uq_formato_descripcion UNIQUE (descripcion),
    CONSTRAINT ck_formato_medidas CHECK (
        (ancho_cm IS NULL AND alto_cm IS NULL)
        OR (ancho_cm > 0 AND alto_cm > 0)
    )
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3) TABLAS DE DATOS DEL NEGOCIO
-- ---------------------------------------------------------------------

CREATE TABLE cliente (
    id_cliente      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    apellido        VARCHAR(60)  NOT NULL,
    nombre          VARCHAR(60)  NOT NULL,
    telefono        VARCHAR(25)  NULL,
    email           VARCHAR(100) NULL,
    es_profesional  BOOLEAN      NOT NULL DEFAULT FALSE,   -- campo "Prof." de la ficha
    id_localidad    INT UNSIGNED NOT NULL,
    id_zona         INT UNSIGNED NULL,
    fecha_alta      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_email UNIQUE (email),
    CONSTRAINT fk_cliente_localidad FOREIGN KEY (id_localidad)
        REFERENCES localidad (id_localidad)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_cliente_zona FOREIGN KEY (id_zona)
        REFERENCES zona (id_zona)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE empleado (
    id_empleado  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    apellido     VARCHAR(60) NOT NULL,
    nombre       VARCHAR(60) NOT NULL,
    cargo        VARCHAR(50) NOT NULL,
    activo       BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id_empleado)
) ENGINE=InnoDB;

-- El N° de pedido arranca en 43646 (el de la ficha de ejemplo) y sigue solo.
CREATE TABLE pedido (
    numero_pedido    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_cliente       INT UNSIGNED NOT NULL,
    id_tipo_trabajo  TINYINT UNSIGNED NOT NULL,
    fecha_entrada    DATE NOT NULL DEFAULT (CURRENT_DATE),  -- cuando el cliente deja el pedido
    fecha_ingreso    DATE NULL,                              -- cuando entra a producción
    fecha_salida     DATE NULL,                              -- cuando se entrega
    observaciones    VARCHAR(255) NULL,
    PRIMARY KEY (numero_pedido),
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_pedido_tipo_trabajo FOREIGN KEY (id_tipo_trabajo)
        REFERENCES tipo_trabajo (id_tipo_trabajo)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_pedido_ingreso CHECK (fecha_ingreso IS NULL OR fecha_ingreso >= fecha_entrada),
    CONSTRAINT ck_pedido_salida  CHECK (fecha_salida  IS NULL OR fecha_salida  >= fecha_entrada)
) ENGINE=InnoDB AUTO_INCREMENT=43646;

CREATE TABLE detalle_pedido (
    numero_pedido         INT UNSIGNED      NOT NULL,
    numero_item           SMALLINT UNSIGNED NOT NULL,
    id_material           INT UNSIGNED      NOT NULL,
    id_formato            INT UNSIGNED      NOT NULL,
    cantidad              INT UNSIGNED      NOT NULL,
    acabado               ENUM('BRILLO','MATE') NULL,
    con_margen            BOOLEAN NOT NULL DEFAULT FALSE,
    ajuste                ENUM('LLENAR_FORMATO','ADAPTAR_IMAGEN') NULL,
    soporte               ENUM('SOLO_IMPRESION','CON_BASTIDOR') NOT NULL DEFAULT 'SOLO_IMPRESION',
    con_iman              BOOLEAN NOT NULL DEFAULT FALSE,
    medida_personalizada  VARCHAR(30)   NULL,   -- se usa cuando el formato es "Otra medida"
    precio_unitario       DECIMAL(10,2) NULL,   -- precio pactado al momento del pedido
    observaciones         VARCHAR(150)  NULL,
    PRIMARY KEY (numero_pedido, numero_item),
    CONSTRAINT fk_detalle_pedido FOREIGN KEY (numero_pedido)
        REFERENCES pedido (numero_pedido)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_detalle_material FOREIGN KEY (id_material)
        REFERENCES material (id_material)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_detalle_formato FOREIGN KEY (id_formato)
        REFERENCES formato (id_formato)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio   CHECK (precio_unitario IS NULL OR precio_unitario >= 0)
) ENGINE=InnoDB;

-- Resuelve la relación N:M Pedido - Empleado - Tipo de tarea.
-- Un pedido tiene, como máximo, una descarga, una impresión y un despacho.
CREATE TABLE pedido_tarea (
    numero_pedido  INT UNSIGNED     NOT NULL,
    id_tipo_tarea  TINYINT UNSIGNED NOT NULL,
    id_empleado    INT UNSIGNED     NOT NULL,
    fecha_hora     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (numero_pedido, id_tipo_tarea),
    CONSTRAINT fk_tarea_pedido FOREIGN KEY (numero_pedido)
        REFERENCES pedido (numero_pedido)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_tarea_tipo FOREIGN KEY (id_tipo_tarea)
        REFERENCES tipo_tarea (id_tipo_tarea)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_tarea_empleado FOREIGN KEY (id_empleado)
        REFERENCES empleado (id_empleado)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Un pedido tiene como máximo una factura (UNIQUE sobre numero_pedido).
CREATE TABLE factura (
    numero_factura  VARCHAR(20)  NOT NULL,
    numero_pedido   INT UNSIGNED NOT NULL,
    id_empleado     INT UNSIGNED NOT NULL,          -- quién facturó
    fecha_emision   DATE         NOT NULL,
    importe_total   DECIMAL(12,2) NOT NULL,
    estado_pago     ENUM('PENDIENTE','PAGADO') NOT NULL DEFAULT 'PENDIENTE',
    fecha_pago      DATE NULL,
    PRIMARY KEY (numero_factura),
    CONSTRAINT uq_factura_pedido UNIQUE (numero_pedido),
    CONSTRAINT fk_factura_pedido FOREIGN KEY (numero_pedido)
        REFERENCES pedido (numero_pedido)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_factura_empleado FOREIGN KEY (id_empleado)
        REFERENCES empleado (id_empleado)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT ck_factura_importe CHECK (importe_total >= 0),
    CONSTRAINT ck_factura_pago CHECK (
        (estado_pago = 'PAGADO'   AND fecha_pago IS NOT NULL AND fecha_pago >= fecha_emision)
        OR (estado_pago = 'PENDIENTE' AND fecha_pago IS NULL)
    )
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4) DATOS DE PRUEBA
-- ---------------------------------------------------------------------

INSERT INTO localidad (id_localidad, nombre, provincia) VALUES
    (1, 'Villa María',     'Córdoba'),
    (2, 'Villa Nueva',     'Córdoba'),
    (3, 'James Craik',     'Córdoba'),
    (4, 'Oliva',           'Córdoba'),
    (5, 'Río Tercero',     'Córdoba'),
    (6, 'Córdoba Capital', 'Córdoba');

INSERT INTO zona (id_zona, nombre, descripcion) VALUES
    (1, 'Centro', 'Microcentro y alrededores'),
    (2, 'Norte',  'Barrios del norte'),
    (3, 'Sur',    'Barrios del sur'),
    (4, 'Este',   'Barrios del este'),
    (5, 'Oeste',  'Barrios del oeste');

INSERT INTO tipo_trabajo (id_tipo_trabajo, nombre) VALUES
    (1, 'IMPRESION'),
    (2, 'AMPLIACION'),
    (3, 'GIGANTOGRAFIA');

INSERT INTO tipo_tarea (id_tipo_tarea, nombre, orden) VALUES
    (1, 'DESCARGA', 1),
    (2, 'IMPRESION', 2),
    (3, 'DESPACHO', 3);

INSERT INTO material (id_material, nombre, descripcion) VALUES
    (1, 'Papel Mate',    'Papel fotográfico mate'),
    (2, 'Papel Brillo',  'Papel fotográfico brillante'),
    (3, 'Lona Front',    'Lona frontlit para gigantografías'),
    (4, 'Lona Blackout', 'Lona opaca blackout'),
    (5, 'Canvas',        'Tela canvas para cuadros'),
    (6, 'Ecocuero',      'Soporte símil cuero'),
    (7, 'Otros',         'Material especial: detallar en observaciones');

INSERT INTO formato (id_formato, descripcion, ancho_cm, alto_cm) VALUES
    (1, '9x13',        9,  13),
    (2, '10x15',      10,  15),
    (3, '13x18',      13,  18),
    (4, '15x21',      15,  21),
    (5, '20x30',      20,  30),
    (6, '30x40',      30,  40),
    (7, '30x45',      30,  45),
    (8, '30x60',      30,  60),
    (9, 'Otra medida', NULL, NULL);

INSERT INTO cliente (id_cliente, apellido, nombre, telefono, email, es_profesional, id_localidad, id_zona) VALUES
    (1, 'Ferreyra', 'Ivana',    '353-4000001', 'ivana.ferreyra@mail.com',     FALSE, 1, 1),
    (2, 'Quiroga',  'Martina',  '353-4000002', 'martina.fotografia@mail.com', TRUE,  2, 2),
    (3, 'Rossi',    'Gustavo',  '353-4000003', NULL,                          FALSE, 1, 3),
    (4, 'Medina',   'Carolina', '353-4000004', 'carolina.medina@mail.com',    FALSE, 3, NULL),
    (5, 'Bustos',   'Facundo',  '353-4000005', 'facu.bustos@mail.com',        TRUE,  4, 4),
    (6, 'Cabrera',  'Julieta',  NULL,          'julieta.cabrera@mail.com',    FALSE, 1, 5);

INSERT INTO empleado (id_empleado, apellido, nombre, cargo) VALUES
    (1, 'Fernández', 'Lucía',  'Atención al cliente'),
    (2, 'Rojas',     'Martín', 'Impresor'),
    (3, 'Díaz',      'Sofía',  'Administración y facturación'),
    (4, 'Álvarez',   'Diego',  'Despacho y reparto'),
    (5, 'Mansilla',  'Carla',  'Operadora de descarga');

-- Pedidos: cada uno muestra una situación distinta del negocio
INSERT INTO pedido (numero_pedido, id_cliente, id_tipo_trabajo, fecha_entrada, fecha_ingreso, fecha_salida, observaciones) VALUES
    (43646, 1, 1, '2026-08-26', '2026-08-26', '2026-08-28', 'Pedido de la ficha de ejemplo: 10 copias de 10x15, pagado'),
    (43647, 2, 2, '2026-09-02', '2026-09-02', NULL,         'Cliente profesional. Impreso, falta despachar'),
    (43648, 3, 3, '2026-09-05', '2026-09-06', NULL,         'Gigantografía para local. Archivos descargados'),
    (43649, 4, 1, '2026-11-09', NULL,         NULL,         'Recién ingresado, todavía sin tareas'),
    (43650, 1, 1, '2026-09-10', '2026-09-10', '2026-09-12', 'Despachado y facturado, pago pendiente'),
    (43651, 2, 3, '2026-09-15', '2026-09-16', '2026-09-19', 'Dos lonas, facturado y pagado'),
    (43652, 6, 2, '2026-10-01', '2026-10-01', '2026-10-03', 'Despachado pero todavía sin facturar');

INSERT INTO detalle_pedido
    (numero_pedido, numero_item, id_material, id_formato, cantidad, acabado, con_margen, ajuste, soporte, con_iman, medida_personalizada, precio_unitario, observaciones)
VALUES
    (43646, 1, 2, 2, 10, NULL,     FALSE, NULL,             'SOLO_IMPRESION', FALSE, NULL,      450.00,   NULL),
    (43647, 1, 5, 7,  2, NULL,     FALSE, 'LLENAR_FORMATO', 'CON_BASTIDOR',   FALSE, NULL,     9500.00,   NULL),
    (43647, 2, 1, 5,  5, 'MATE',   TRUE,  NULL,             'SOLO_IMPRESION', FALSE, NULL,     1800.00,   NULL),
    (43648, 1, 3, 9,  1, NULL,     FALSE, NULL,             'SOLO_IMPRESION', FALSE, '3x2 m', 38000.00,   'Para fachada de local'),
    (43649, 1, 1, 1, 50, 'MATE',   TRUE,  NULL,             'SOLO_IMPRESION', FALSE, NULL,      250.00,   NULL),
    (43649, 2, 2, 2, 30, 'BRILLO', FALSE, 'LLENAR_FORMATO', 'SOLO_IMPRESION', FALSE, NULL,      450.00,   NULL),
    (43649, 3, 2, 3, 12, 'BRILLO', FALSE, 'ADAPTAR_IMAGEN', 'SOLO_IMPRESION', TRUE,  NULL,      900.00,   'Fotos con imán'),
    (43650, 1, 2, 4, 20, 'BRILLO', FALSE, NULL,             'SOLO_IMPRESION', FALSE, NULL,      700.00,   NULL),
    (43651, 1, 4, 9,  1, NULL,     FALSE, NULL,             'CON_BASTIDOR',   FALSE, '4x1,5 m', 52000.00, NULL),
    (43651, 2, 3, 9,  2, NULL,     FALSE, NULL,             'SOLO_IMPRESION', FALSE, '2x1 m',  18000.00,  NULL),
    (43652, 1, 2, 6,  3, 'BRILLO', TRUE,  NULL,             'SOLO_IMPRESION', FALSE, NULL,     6500.00,   NULL),
    (43652, 2, 6, 8,  1, NULL,     FALSE, NULL,             'CON_BASTIDOR',   FALSE, NULL,    14000.00,   NULL);

-- Tareas: 1 = descarga, 2 = impresión, 3 = despacho
INSERT INTO pedido_tarea (numero_pedido, id_tipo_tarea, id_empleado, fecha_hora) VALUES
    (43646, 1, 1, '2026-08-26 10:15:00'),
    (43646, 2, 2, '2026-08-26 15:40:00'),
    (43646, 3, 4, '2026-08-28 09:30:00'),
    (43647, 1, 5, '2026-09-02 11:00:00'),
    (43647, 2, 2, '2026-09-03 16:20:00'),
    (43648, 1, 1, '2026-09-06 09:10:00'),
    (43650, 1, 5, '2026-09-10 10:00:00'),
    (43650, 2, 2, '2026-09-11 14:30:00'),
    (43650, 3, 4, '2026-09-12 11:45:00'),
    (43651, 1, 1, '2026-09-16 09:00:00'),
    (43651, 2, 2, '2026-09-17 13:10:00'),
    (43651, 3, 4, '2026-09-19 10:20:00'),
    (43652, 1, 5, '2026-10-01 12:00:00'),
    (43652, 2, 2, '2026-10-02 15:00:00'),
    (43652, 3, 4, '2026-10-03 10:00:00');

-- Facturas (el importe coincide con la suma de los ítems de cada pedido)
INSERT INTO factura (numero_factura, numero_pedido, id_empleado, fecha_emision, importe_total, estado_pago, fecha_pago) VALUES
    ('0001-00000101', 43646, 3, '2026-08-28',  4500.00, 'PAGADO',    '2026-08-28'),
    ('0001-00000102', 43650, 3, '2026-09-12', 14000.00, 'PENDIENTE', NULL),
    ('0001-00000103', 43651, 3, '2026-09-19', 88000.00, 'PAGADO',    '2026-09-20');

-- ---------------------------------------------------------------------
-- 5) VISTAS
-- ---------------------------------------------------------------------

-- El estado NO se carga a mano: se deduce de las tareas y de la factura.
CREATE OR REPLACE VIEW v_estado_pedido AS
SELECT  p.numero_pedido,
        CONCAT(c.apellido, ', ', c.nombre) AS cliente,
        tt.nombre AS tipo_trabajo,
        p.fecha_entrada,
        p.fecha_salida,
        CASE
            WHEN t3.numero_pedido IS NOT NULL THEN 'DESPACHADO'
            WHEN t2.numero_pedido IS NOT NULL THEN 'IMPRESO'
            WHEN t1.numero_pedido IS NOT NULL THEN 'DESCARGADO'
            ELSE 'INGRESADO'
        END AS estado_produccion,
        CASE WHEN f.numero_factura IS NULL THEN 'SIN FACTURAR' ELSE 'FACTURADO' END AS facturacion,
        COALESCE(f.estado_pago, 'SIN FACTURA') AS estado_pago
FROM pedido p
JOIN cliente c        ON c.id_cliente = p.id_cliente
JOIN tipo_trabajo tt  ON tt.id_tipo_trabajo = p.id_tipo_trabajo
LEFT JOIN pedido_tarea t1 ON t1.numero_pedido = p.numero_pedido AND t1.id_tipo_tarea = 1
LEFT JOIN pedido_tarea t2 ON t2.numero_pedido = p.numero_pedido AND t2.id_tipo_tarea = 2
LEFT JOIN pedido_tarea t3 ON t3.numero_pedido = p.numero_pedido AND t3.id_tipo_tarea = 3
LEFT JOIN factura f   ON f.numero_pedido = p.numero_pedido;

-- Total calculado de cada pedido a partir de sus ítems
CREATE OR REPLACE VIEW v_total_pedido AS
SELECT  numero_pedido,
        COUNT(*)                          AS cantidad_items,
        SUM(cantidad)                     AS cantidad_total,
        SUM(cantidad * precio_unitario)   AS importe_calculado
FROM detalle_pedido
GROUP BY numero_pedido;

-- ---------------------------------------------------------------------
-- 6) TRIGGERS (reglas de negocio)
-- ---------------------------------------------------------------------
DELIMITER //

-- Regla: no se puede imprimir sin descargar ni despachar sin imprimir.
-- (Los id de tipo_tarea siguen el orden 1, 2, 3)
CREATE TRIGGER trg_tarea_respeta_orden
BEFORE INSERT ON pedido_tarea
FOR EACH ROW
BEGIN
    IF NEW.id_tipo_tarea > 1 THEN
        IF NOT EXISTS (SELECT 1
                       FROM pedido_tarea
                       WHERE numero_pedido = NEW.numero_pedido
                         AND id_tipo_tarea = NEW.id_tipo_tarea - 1) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Falta la etapa anterior (descarga -> impresion -> despacho)';
        END IF;
    END IF;
END//

-- Regla: no se puede facturar un pedido que no tiene ítems.
CREATE TRIGGER trg_factura_requiere_items
BEFORE INSERT ON factura
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1
                   FROM detalle_pedido
                   WHERE numero_pedido = NEW.numero_pedido) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede facturar un pedido sin items';
    END IF;
END//

DELIMITER ;

-- ---------------------------------------------------------------------
-- 7) CONSULTAS DE DEMOSTRACIÓN
-- ---------------------------------------------------------------------

-- 7.1 Estado de todos los pedidos (deducido, no cargado a mano)
SELECT * FROM v_estado_pedido ORDER BY numero_pedido;

-- 7.2 Historial: cantidad de pedidos por cliente (incluye clientes sin pedidos)
SELECT  c.id_cliente,
        CONCAT(c.apellido, ', ', c.nombre) AS cliente,
        COUNT(p.numero_pedido) AS cantidad_pedidos
FROM cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.apellido, c.nombre
ORDER BY cantidad_pedidos DESC, cliente;

-- 7.3 Ficha completa del pedido 43649 (ítems con material y formato)
SELECT  d.numero_pedido, d.numero_item, m.nombre AS material, f.descripcion AS formato,
        d.cantidad, d.acabado, d.con_margen, d.ajuste, d.soporte, d.con_iman, d.precio_unitario
FROM detalle_pedido d
JOIN material m ON m.id_material = d.id_material
JOIN formato  f ON f.id_formato  = d.id_formato
WHERE d.numero_pedido = 43649
ORDER BY d.numero_item;

-- 7.4 Quién descargó, imprimió y despachó cada pedido (control interno)
SELECT  pt.numero_pedido, tt.nombre AS tarea,
        CONCAT(e.apellido, ', ', e.nombre) AS empleado, pt.fecha_hora
FROM pedido_tarea pt
JOIN tipo_tarea tt ON tt.id_tipo_tarea = pt.id_tipo_tarea
JOIN empleado e    ON e.id_empleado    = pt.id_empleado
ORDER BY pt.numero_pedido, tt.orden;

-- 7.5 Facturas con pago pendiente y a quién se le cobra
SELECT  f.numero_factura, f.numero_pedido, CONCAT(c.apellido, ', ', c.nombre) AS cliente,
        f.importe_total, f.fecha_emision
FROM factura f
JOIN pedido p  ON p.numero_pedido = f.numero_pedido
JOIN cliente c ON c.id_cliente    = p.id_cliente
WHERE f.estado_pago = 'PENDIENTE';

-- 7.6 Control: importe facturado vs. suma de ítems 
SELECT  f.numero_factura, f.importe_total, t.importe_calculado
FROM factura f
JOIN v_total_pedido t ON t.numero_pedido = f.numero_pedido
WHERE f.importe_total <> t.importe_calculado;

-- 7.7 Cantidad de unidades pedidas por material
SELECT  m.nombre AS material, SUM(d.cantidad) AS unidades
FROM detalle_pedido d
JOIN material m ON m.id_material = d.id_material
GROUP BY m.id_material, m.nombre
ORDER BY unidades DESC;

-- 7.8 Tareas realizadas por empleado
SELECT  CONCAT(e.apellido, ', ', e.nombre) AS empleado, tt.nombre AS tarea, COUNT(*) AS cantidad
FROM pedido_tarea pt
JOIN empleado e    ON e.id_empleado    = pt.id_empleado
JOIN tipo_tarea tt ON tt.id_tipo_tarea = pt.id_tipo_tarea
GROUP BY e.id_empleado, e.apellido, e.nombre, tt.nombre
ORDER BY empleado, tarea;

