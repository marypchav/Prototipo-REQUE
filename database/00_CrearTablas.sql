/*
Crea la base de datos BDCapanni y todas sus tablas.

Orden de ejecución del proyecto:
    1. 00_CrearTablas.sql
    2. 01_CargarCatalogos.sql
    3. funciones (fn/fn*.sql)
    4. triggers  (tr/tr*.sql)
    5. procedimientos (sp/sp*.sql)
    6. 99_PruebaFlujo.sql (opcional, prueba de punta a punta)

Se ejecuta sobre una base vacía. Para empezar de cero:
    USE master; DROP DATABASE BDCapanni;

Nota: OPENJSON (usado en spAgregarProducto) necesita nivel de compatibilidad
130 o mayor (SQL Server 2016+). Una base nueva ya lo trae por defecto.
*/
USE master;
GO

IF (DB_ID('BDCapanni') IS NULL)
BEGIN
    CREATE DATABASE BDCapanni;
END;
GO

USE BDCapanni;
GO

--------------------------------------------------------------------------------
-- tabla de errores (la usan todos los BEGIN CATCH)
--------------------------------------------------------------------------------
CREATE TABLE dbo.dbError (
    IdError INT IDENTITY(1, 1) NOT NULL
    , UserName VARCHAR(128) NULL
    , ErrorNumber INT NULL
    , ErrorState INT NULL
    , ErrorSeverity INT NULL
    , ErrorLine INT NULL
    , ErrorProcedure VARCHAR(128) NULL
    , ErrorMessage NVARCHAR(4000) NULL
    , ErrorDateTime DATETIME NOT NULL
    , CONSTRAINT PK_dbError PRIMARY KEY (IdError)
);
GO

--------------------------------------------------------------------------------
-- catálogos: ids fijos, se cargan en 01_CargarCatalogos.sql
--------------------------------------------------------------------------------

-- tipos de operación que quedan en la bitácora
CREATE TABLE dbo.TipoOperacion (
    IdTipoOperacion INT NOT NULL
    , Nombre NVARCHAR(64) NOT NULL
    , CONSTRAINT PK_TipoOperacion PRIMARY KEY (IdTipoOperacion)
);

-- provincias de Costa Rica (GP003: provincia, cantón, distrito, otras señas)
CREATE TABLE dbo.Provincia (
    IdProvincia INT NOT NULL
    , Nombre NVARCHAR(32) NOT NULL
    , CONSTRAINT PK_Provincia PRIMARY KEY (IdProvincia)
);

-- categorías de prenda (CP007)
CREATE TABLE dbo.Categoria (
    IdCategoria INT NOT NULL
    , Nombre NVARCHAR(64) NOT NULL
    , CONSTRAINT PK_Categoria PRIMARY KEY (IdCategoria)
    , CONSTRAINT UQ_Categoria_Nombre UNIQUE (Nombre)
);

-- tallas (CP003, CP006). Orden sirve para mostrar XS antes que XL
CREATE TABLE dbo.Talla (
    IdTalla INT NOT NULL
    , Nombre NVARCHAR(16) NOT NULL
    , Orden INT NOT NULL
    , CONSTRAINT PK_Talla PRIMARY KEY (IdTalla)
    , CONSTRAINT UQ_Talla_Nombre UNIQUE (Nombre)
);

-- métodos de pago (GP011). FlagSoloRetiro = efectivo solo con retiro en el taller
CREATE TABLE dbo.MetodoPago (
    IdMetodoPago INT NOT NULL
    , Nombre NVARCHAR(32) NOT NULL
    , FlagRequiereComprobante BIT NOT NULL
    , FlagSoloRetiro BIT NOT NULL
    , CONSTRAINT PK_MetodoPago PRIMARY KEY (IdMetodoPago)
);

-- métodos de entrega (GP012). CostoEnvio NULL = "Envío a coordinar" (GP020)
CREATE TABLE dbo.MetodoEntrega (
    IdMetodoEntrega INT NOT NULL
    , Nombre NVARCHAR(64) NOT NULL
    , FlagRequiereDireccion BIT NOT NULL
    , CostoEnvio MONEY NULL
    , CONSTRAINT PK_MetodoEntrega PRIMARY KEY (IdMetodoEntrega)
    , CONSTRAINT CK_MetodoEntrega_Costo CHECK ((CostoEnvio IS NULL) OR (CostoEnvio >= 0))
);

-- estados del pedido (GP017). Los flags evitan "quemar" reglas en los SP
CREATE TABLE dbo.EstadoPedido (
    IdEstadoPedido INT NOT NULL
    , Nombre NVARCHAR(32) NOT NULL
    , FlagRequiereMotivo BIT NOT NULL -- Rechazado / Cancelado
    , FlagDevuelveInventario BIT NOT NULL -- Rechazado / Cancelado
    , CONSTRAINT PK_EstadoPedido PRIMARY KEY (IdEstadoPedido)
);

-- transiciones permitidas entre estados (GP017: solo avanzan, no retroceden).
-- FlagSoloEnvio / FlagSoloRetiro: "Enviado" solo aplica a pedidos con envío y
-- "Listo para retiro" solo a pedidos que se retiran en el taller
CREATE TABLE dbo.TransicionEstadoPedido (
    IdEstadoActual INT NOT NULL
    , IdEstadoNuevo INT NOT NULL
    , FlagSoloEnvio BIT NOT NULL
    , FlagSoloRetiro BIT NOT NULL
    , CONSTRAINT PK_TransicionEstadoPedido PRIMARY KEY (IdEstadoActual, IdEstadoNuevo)
    , CONSTRAINT FK_Transicion_EstadoActual FOREIGN KEY (IdEstadoActual)
        REFERENCES dbo.EstadoPedido (IdEstadoPedido)
    , CONSTRAINT FK_Transicion_EstadoNuevo FOREIGN KEY (IdEstadoNuevo)
        REFERENCES dbo.EstadoPedido (IdEstadoPedido)
);
GO

--------------------------------------------------------------------------------
-- usuarios y direcciones
--------------------------------------------------------------------------------

-- PassHash guarda el hash bcrypt generado en Node (sección 2.4 de la ERS:
-- las contraseñas nunca se guardan en texto plano)
CREATE TABLE dbo.Usuario (
    IdUsuario INT IDENTITY(1, 1) NOT NULL
    , Nombre NVARCHAR(100) NOT NULL
    , Correo VARCHAR(128) NOT NULL
    , Telefono VARCHAR(16) NOT NULL
    , PassHash VARCHAR(100) NOT NULL
    , EsAdministrador BIT NOT NULL CONSTRAINT DF_Usuario_EsAdministrador DEFAULT (0)
    , FlagActivo BIT NOT NULL CONSTRAINT DF_Usuario_FlagActivo DEFAULT (1)
    , FechaCreacion DATETIME NOT NULL CONSTRAINT DF_Usuario_FechaCreacion DEFAULT (GETDATE())
    , CONSTRAINT PK_Usuario PRIMARY KEY (IdUsuario)
    , CONSTRAINT UQ_Usuario_Correo UNIQUE (Correo) -- GP001: correo único
);

-- eliminación lógica: un pedido viejo guarda su propia copia de la dirección
-- (GP005/GP006: los pedidos ya hechos no se ven afectados)
CREATE TABLE dbo.Direccion (
    IdDireccion INT IDENTITY(1, 1) NOT NULL
    , IdUsuario INT NOT NULL
    , IdProvincia INT NOT NULL
    , Canton NVARCHAR(64) NOT NULL
    , Distrito NVARCHAR(64) NOT NULL
    , OtrasSenas NVARCHAR(256) NOT NULL
    , FlagActivo BIT NOT NULL CONSTRAINT DF_Direccion_FlagActivo DEFAULT (1)
    , FechaCreacion DATETIME NOT NULL CONSTRAINT DF_Direccion_FechaCreacion DEFAULT (GETDATE())
    , CONSTRAINT PK_Direccion PRIMARY KEY (IdDireccion)
    , CONSTRAINT FK_Direccion_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES dbo.Usuario (IdUsuario)
    , CONSTRAINT FK_Direccion_Provincia FOREIGN KEY (IdProvincia)
        REFERENCES dbo.Provincia (IdProvincia)
);
GO

--------------------------------------------------------------------------------
-- inventario
--------------------------------------------------------------------------------

-- eliminación lógica (FlagActivo): el historial de ventas debe ser inmutable
-- (sección 2.4), así que un producto vendido no se puede borrar físicamente.
-- RutaImagen: ruta del archivo en el servidor (GI003); NULL = "Imagen no disponible"
CREATE TABLE dbo.Producto (
    IdProducto INT IDENTITY(1, 1) NOT NULL
    , IdCategoria INT NOT NULL
    , Nombre NVARCHAR(100) NOT NULL
    , Descripcion NVARCHAR(500) NULL
    , Precio MONEY NOT NULL
    , RutaImagen VARCHAR(260) NULL
    , FlagActivo BIT NOT NULL CONSTRAINT DF_Producto_FlagActivo DEFAULT (1)
    , FechaCreacion DATETIME NOT NULL CONSTRAINT DF_Producto_FechaCreacion DEFAULT (GETDATE())
    , FechaDesactivacion DATETIME NULL
    , CONSTRAINT PK_Producto PRIMARY KEY (IdProducto)
    , CONSTRAINT FK_Producto_Categoria FOREIGN KEY (IdCategoria)
        REFERENCES dbo.Categoria (IdCategoria)
    , CONSTRAINT CK_Producto_Precio CHECK (Precio > 0) -- GI002: precio positivo
);

-- existencias por talla (CP003: solo se muestran tallas con cantidad > 0)
CREATE TABLE dbo.ProductoTalla (
    IdProductoTalla INT IDENTITY(1, 1) NOT NULL
    , IdProducto INT NOT NULL
    , IdTalla INT NOT NULL
    , Cantidad INT NOT NULL
    , CONSTRAINT PK_ProductoTalla PRIMARY KEY (IdProductoTalla)
    , CONSTRAINT FK_ProductoTalla_Producto FOREIGN KEY (IdProducto)
        REFERENCES dbo.Producto (IdProducto)
    , CONSTRAINT FK_ProductoTalla_Talla FOREIGN KEY (IdTalla)
        REFERENCES dbo.Talla (IdTalla)
    , CONSTRAINT UQ_ProductoTalla UNIQUE (IdProducto, IdTalla)
    , CONSTRAINT CK_ProductoTalla_Cantidad CHECK (Cantidad >= 0) -- GI007: entero >= 0
);
GO

--------------------------------------------------------------------------------
-- carrito (GP007 a GP010). Una fila por producto+talla de cada cliente.
-- No reserva existencias: eso se garantiza al confirmar la orden (GP014)
--------------------------------------------------------------------------------
CREATE TABLE dbo.CarritoDetalle (
    IdCarritoDetalle INT IDENTITY(1, 1) NOT NULL
    , IdUsuario INT NOT NULL
    , IdProductoTalla INT NOT NULL
    , Cantidad INT NOT NULL
    , FechaAgregado DATETIME NOT NULL CONSTRAINT DF_CarritoDetalle_Fecha DEFAULT (GETDATE())
    , CONSTRAINT PK_CarritoDetalle PRIMARY KEY (IdCarritoDetalle)
    , CONSTRAINT FK_CarritoDetalle_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES dbo.Usuario (IdUsuario)
    , CONSTRAINT FK_CarritoDetalle_ProductoTalla FOREIGN KEY (IdProductoTalla)
        REFERENCES dbo.ProductoTalla (IdProductoTalla)
    , CONSTRAINT UQ_CarritoDetalle UNIQUE (IdUsuario, IdProductoTalla)
    , CONSTRAINT CK_CarritoDetalle_Cantidad CHECK (Cantidad > 0)
);
GO

--------------------------------------------------------------------------------
-- pedidos
--------------------------------------------------------------------------------

-- DireccionEntrega es una copia en texto: si el cliente cambia o borra la
-- dirección después, el pedido conserva la original (GP005 restricción 3)
CREATE TABLE dbo.Pedido (
    IdPedido INT IDENTITY(1, 1) NOT NULL -- es el "número de pedido" que ve el cliente
    , IdUsuario INT NOT NULL
    , IdEstadoPedido INT NOT NULL
    , IdMetodoPago INT NOT NULL
    , IdMetodoEntrega INT NOT NULL
    , DireccionEntrega NVARCHAR(400) NULL -- NULL si es retiro en el taller
    , SubtotalProductos MONEY NOT NULL
    , CostoEnvio MONEY NULL -- NULL = envío a coordinar
    , Total MONEY NOT NULL
    , MotivoEstado NVARCHAR(300) NULL -- motivo de rechazo o cancelación
    , FechaCreacion DATETIME NOT NULL CONSTRAINT DF_Pedido_FechaCreacion DEFAULT (GETDATE())
    , CONSTRAINT PK_Pedido PRIMARY KEY (IdPedido)
    , CONSTRAINT FK_Pedido_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES dbo.Usuario (IdUsuario)
    , CONSTRAINT FK_Pedido_EstadoPedido FOREIGN KEY (IdEstadoPedido)
        REFERENCES dbo.EstadoPedido (IdEstadoPedido)
    , CONSTRAINT FK_Pedido_MetodoPago FOREIGN KEY (IdMetodoPago)
        REFERENCES dbo.MetodoPago (IdMetodoPago)
    , CONSTRAINT FK_Pedido_MetodoEntrega FOREIGN KEY (IdMetodoEntrega)
        REFERENCES dbo.MetodoEntrega (IdMetodoEntrega)
    , CONSTRAINT CK_Pedido_Total CHECK (Total >= 0)
);

-- copia del nombre, talla y precio del momento de la compra (sección 2.4:
-- el historial guarda los detalles completos del momento de la transacción)
CREATE TABLE dbo.PedidoDetalle (
    IdPedidoDetalle INT IDENTITY(1, 1) NOT NULL
    , IdPedido INT NOT NULL
    , IdProductoTalla INT NOT NULL
    , NombreProducto NVARCHAR(100) NOT NULL
    , NombreTalla NVARCHAR(16) NOT NULL
    , PrecioUnitario MONEY NOT NULL
    , Cantidad INT NOT NULL
    , Subtotal MONEY NOT NULL
    , CONSTRAINT PK_PedidoDetalle PRIMARY KEY (IdPedidoDetalle)
    , CONSTRAINT FK_PedidoDetalle_Pedido FOREIGN KEY (IdPedido)
        REFERENCES dbo.Pedido (IdPedido)
    , CONSTRAINT FK_PedidoDetalle_ProductoTalla FOREIGN KEY (IdProductoTalla)
        REFERENCES dbo.ProductoTalla (IdProductoTalla)
    , CONSTRAINT CK_PedidoDetalle_Cantidad CHECK (Cantidad > 0)
);

-- comprobante SINPE Móvil (GP013). Uno por pedido
CREATE TABLE dbo.Comprobante (
    IdComprobante INT IDENTITY(1, 1) NOT NULL
    , IdPedido INT NOT NULL
    , RutaArchivo VARCHAR(260) NOT NULL
    , FechaSubida DATETIME NOT NULL CONSTRAINT DF_Comprobante_Fecha DEFAULT (GETDATE())
    , CONSTRAINT PK_Comprobante PRIMARY KEY (IdComprobante)
    , CONSTRAINT FK_Comprobante_Pedido FOREIGN KEY (IdPedido)
        REFERENCES dbo.Pedido (IdPedido)
    , CONSTRAINT UQ_Comprobante_Pedido UNIQUE (IdPedido)
);

-- cada cambio de estado con quién y cuándo (GP016, GP017)
CREATE TABLE dbo.HistorialEstadoPedido (
    IdHistorialEstadoPedido INT IDENTITY(1, 1) NOT NULL
    , IdPedido INT NOT NULL
    , IdEstadoPedido INT NOT NULL
    , IdUsuario INT NOT NULL -- quién hizo el cambio
    , Comentario NVARCHAR(300) NULL
    , FechaHora DATETIME NOT NULL CONSTRAINT DF_HistorialEstado_Fecha DEFAULT (GETDATE())
    , CONSTRAINT PK_HistorialEstadoPedido PRIMARY KEY (IdHistorialEstadoPedido)
    , CONSTRAINT FK_HistorialEstado_Pedido FOREIGN KEY (IdPedido)
        REFERENCES dbo.Pedido (IdPedido)
    , CONSTRAINT FK_HistorialEstado_Estado FOREIGN KEY (IdEstadoPedido)
        REFERENCES dbo.EstadoPedido (IdEstadoPedido)
    , CONSTRAINT FK_HistorialEstado_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES dbo.Usuario (IdUsuario)
);

-- cola de correos (GP019). La base solo la llena; el backend (Node) envía los
-- pendientes, marca FlagEnviado y suma Intentos si falla (flujo alternativo)
CREATE TABLE dbo.Notificacion (
    IdNotificacion INT IDENTITY(1, 1) NOT NULL
    , IdPedido INT NOT NULL
    , Correo VARCHAR(128) NOT NULL
    , Asunto NVARCHAR(128) NOT NULL
    , Mensaje NVARCHAR(600) NOT NULL
    , FlagEnviado BIT NOT NULL CONSTRAINT DF_Notificacion_FlagEnviado DEFAULT (0)
    , Intentos INT NOT NULL CONSTRAINT DF_Notificacion_Intentos DEFAULT (0)
    , FechaCreacion DATETIME NOT NULL CONSTRAINT DF_Notificacion_Fecha DEFAULT (GETDATE())
    , FechaEnvio DATETIME NULL
    , CONSTRAINT PK_Notificacion PRIMARY KEY (IdNotificacion)
    , CONSTRAINT FK_Notificacion_Pedido FOREIGN KEY (IdPedido)
        REFERENCES dbo.Pedido (IdPedido)
);
GO

--------------------------------------------------------------------------------
-- auditoría
--------------------------------------------------------------------------------
CREATE TABLE dbo.Bitacora (
    IdBitacora INT IDENTITY(1, 1) NOT NULL
    , IdUsuario INT NOT NULL
    , IdTipoOperacion INT NOT NULL
    , IP VARCHAR(64) NULL
    , DatosAntes NVARCHAR(MAX) NULL
    , DatosDespues NVARCHAR(MAX) NULL
    , FechaHora DATETIME NOT NULL CONSTRAINT DF_Bitacora_FechaHora DEFAULT (GETDATE())
    , CONSTRAINT PK_Bitacora PRIMARY KEY (IdBitacora)
    , CONSTRAINT FK_Bitacora_Usuario FOREIGN KEY (IdUsuario)
        REFERENCES dbo.Usuario (IdUsuario)
    , CONSTRAINT FK_Bitacora_TipoOperacion FOREIGN KEY (IdTipoOperacion)
        REFERENCES dbo.TipoOperacion (IdTipoOperacion)
);
GO

--------------------------------------------------------------------------------
-- índices para las consultas más frecuentes
--------------------------------------------------------------------------------
CREATE INDEX IX_Producto_Activo ON dbo.Producto (FlagActivo, IdCategoria);
CREATE INDEX IX_Direccion_Usuario ON dbo.Direccion (IdUsuario, FlagActivo);
CREATE INDEX IX_Pedido_Usuario ON dbo.Pedido (IdUsuario, FechaCreacion DESC);
CREATE INDEX IX_Pedido_Estado ON dbo.Pedido (IdEstadoPedido);
CREATE INDEX IX_PedidoDetalle_Pedido ON dbo.PedidoDetalle (IdPedido);
CREATE INDEX IX_Historial_Pedido ON dbo.HistorialEstadoPedido (IdPedido, FechaHora);
CREATE INDEX IX_Notificacion_Pendiente ON dbo.Notificacion (FlagEnviado, Intentos);
GO
