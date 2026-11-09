/* Script único: crea BDCapanni con tablas, catálogos, funciones, trigger y SP. Ejecutar completo en SSMS (F5) sobre un servidor sin la base. */
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

/*
Carga los catálogos de BDCapanni y la cuenta de la administradora.
Se ejecuta una sola vez, después de 00_CrearTablas.sql.
*/
USE BDCapanni;
GO

SET NOCOUNT ON;

BEGIN TRY

    BEGIN TRANSACTION tCargarCatalogos;

        -- tipos de operación de la bitácora
        INSERT INTO dbo.TipoOperacion (IdTipoOperacion, Nombre)
        VALUES (1, N'Registrar cliente')
            , (2, N'Agregar producto')
            , (3, N'Modificar producto')
            , (4, N'Eliminar producto')
            , (5, N'Actualizar disponibilidad')
            , (6, N'Subir foto de producto')
            , (7, N'Agregar dirección')
            , (8, N'Modificar dirección')
            , (9, N'Eliminar dirección')
            , (10, N'Confirmar orden de compra')
            , (11, N'Cambiar estado de pedido');

        INSERT INTO dbo.Provincia (IdProvincia, Nombre)
        VALUES (1, N'San José')
            , (2, N'Alajuela')
            , (3, N'Cartago')
            , (4, N'Heredia')
            , (5, N'Guanacaste')
            , (6, N'Puntarenas')
            , (7, N'Limón');

        -- AJUSTAR con las categorías reales que maneja Confecciones Capanni
        INSERT INTO dbo.Categoria (IdCategoria, Nombre)
        VALUES (1, N'Blusas')
            , (2, N'Vestidos')
            , (3, N'Pantalones')
            , (4, N'Faldas')
            , (5, N'Accesorios');

        -- AJUSTAR con las tallas reales
        INSERT INTO dbo.Talla (IdTalla, Nombre, Orden)
        VALUES (1, N'XS', 1)
            , (2, N'S', 2)
            , (3, N'M', 3)
            , (4, N'L', 4)
            , (5, N'XL', 5)
            , (6, N'Única', 6);

        -- GP011: efectivo solo si se retira en el taller
        INSERT INTO dbo.MetodoPago (IdMetodoPago, Nombre, FlagRequiereComprobante, FlagSoloRetiro)
        VALUES (1, N'SINPE Móvil', 1, 0)
            , (2, N'Efectivo', 0, 1);

        -- GP012. CostoEnvio NULL = "Envío a coordinar con la administradora" (GP020).
        -- Si la clienta define tarifas fijas, se ponen aquí
        INSERT INTO dbo.MetodoEntrega (IdMetodoEntrega, Nombre, FlagRequiereDireccion, CostoEnvio)
        VALUES (1, N'Correos de Costa Rica', 1, NULL)
            , (2, N'Encomienda', 1, NULL)
            , (3, N'Plataforma de transporte', 1, NULL)
            , (4, N'Retiro en el taller', 0, 0);

        -- GP017
        INSERT INTO dbo.EstadoPedido (IdEstadoPedido, Nombre, FlagRequiereMotivo, FlagDevuelveInventario)
        VALUES (1, N'Pendiente de confirmación', 0, 0)
            , (2, N'Confirmado', 0, 0)
            , (3, N'En preparación', 0, 0)
            , (4, N'Enviado', 0, 0)
            , (5, N'Listo para retiro', 0, 0)
            , (6, N'Entregado', 0, 0)
            , (7, N'Rechazado', 1, 1)
            , (8, N'Cancelado', 1, 1);

        -- transiciones válidas (los estados solo avanzan)
        INSERT INTO dbo.TransicionEstadoPedido (IdEstadoActual, IdEstadoNuevo, FlagSoloEnvio, FlagSoloRetiro)
        VALUES (1, 2, 0, 0) -- pendiente -> confirmado (GP016)
            , (1, 7, 0, 0) -- pendiente -> rechazado (GP016 flujo alternativo)
            , (2, 3, 0, 0) -- confirmado -> en preparación
            , (2, 8, 0, 0) -- confirmado -> cancelado
            , (3, 4, 1, 0) -- en preparación -> enviado (solo con envío)
            , (3, 5, 0, 1) -- en preparación -> listo para retiro (solo retiro)
            , (3, 8, 0, 0) -- en preparación -> cancelado
            , (4, 6, 1, 0) -- enviado -> entregado
            , (5, 6, 0, 1); -- listo para retiro -> entregado

        -- cuenta de la administradora (GI001: ya existe en la base de datos).
        -- REEMPLAZAR el hash por uno real generado con bcrypt, por ejemplo:
        --   node -e "console.log(require('bcrypt').hashSync('SuContraseña', 10))"
        INSERT INTO dbo.Usuario (Nombre, Correo, Telefono, PassHash, EsAdministrador)
        VALUES (
            N'Carmen Acuña Padilla'
            , 'admin@capanni.com'
            , '88888888'
            , '$2b$10$REEMPLAZAR_POR_HASH_REAL_GENERADO_CON_BCRYPT'
            , 1
        );

    COMMIT TRANSACTION tCargarCatalogos;

END TRY
BEGIN CATCH

    IF (@@TRANCOUNT > 0)
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    INSERT INTO dbo.dbError (
        UserName
        , ErrorNumber
        , ErrorState
        , ErrorSeverity
        , ErrorLine
        , ErrorProcedure
        , ErrorMessage
        , ErrorDateTime
    )
    VALUES (
        SUSER_SNAME()
        , ERROR_NUMBER()
        , ERROR_STATE()
        , ERROR_SEVERITY()
        , ERROR_LINE()
        , ERROR_PROCEDURE()
        , ERROR_MESSAGE()
        , GETDATE()
    );

    SELECT ERROR_MESSAGE() AS Error;

END CATCH;

SET NOCOUNT OFF;
GO

USE BDCapanni;
GO

-------------------------------------------------------------------------------
-- fn/fnJsonDireccion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fnJsonDireccion (
    @inIdDireccion INT -- dirección de la que se arma el JSON
)
RETURNS NVARCHAR(MAX)
AS
/*
Devuelve el estado completo de una dirección en JSON, para la bitácora.

Ejemplo:
    SELECT dbo.fnJsonDireccion(1) AS Json;
*/
BEGIN
    DECLARE @json NVARCHAR(MAX);

    SET @json = (
        SELECT D.IdDireccion
            , D.IdUsuario
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
            , D.FlagActivo
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdDireccion = @inIdDireccion)
        FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
    );

    RETURN @json;
END;
GO

-------------------------------------------------------------------------------
-- fn/fnJsonProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fnJsonProducto (
    @inIdProducto INT -- producto del que se arma el JSON
)
RETURNS NVARCHAR(MAX)
AS
/*
Devuelve el estado completo de un producto (con sus tallas) en JSON.
La usan los SP de inventario para llenar DatosAntes y DatosDespues de la
bitácora, así el formato del JSON es el mismo en todos.

Ejemplo:
    SELECT dbo.fnJsonProducto(1) AS Json;
*/
BEGIN
    DECLARE @json NVARCHAR(MAX);

    -- el subquery con FOR JSON queda incrustado como arreglo (no como texto)
    SET @json = (
        SELECT P.IdProducto
            , C.Nombre AS Categoria
            , P.Nombre
            , P.Descripcion
            , P.Precio
            , P.RutaImagen
            , P.FlagActivo
            , (
                SELECT T.Nombre AS Talla
                    , PT.Cantidad
                FROM dbo.ProductoTalla AS PT
                INNER JOIN dbo.Talla AS T
                    ON (T.IdTalla = PT.IdTalla)
                WHERE (PT.IdProducto = P.IdProducto)
                ORDER BY T.Orden
                FOR JSON PATH
              ) AS Tallas
        FROM dbo.Producto AS P
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        WHERE (P.IdProducto = @inIdProducto)
        FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
    );

    RETURN @json;
END;
GO

-------------------------------------------------------------------------------
-- tr/trPedidoPrimerEstado.sql
-------------------------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trPedidoPrimerEstado
ON dbo.Pedido
AFTER INSERT
AS
/*
Registra en el historial el primer estado de cada pedido ("Pendiente de
confirmación"), para que el historial del cliente (GP018) muestre desde
cuándo existe el pedido.

Ejemplo:
    INSERT INTO dbo.Pedido (IdUsuario, IdEstadoPedido, IdMetodoPago, IdMetodoEntrega
        , DireccionEntrega, SubtotalProductos, CostoEnvio, Total)
    VALUES (2, 1, 2, 4, NULL, 15000, 0, 15000);
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- si el INSERT no insertó filas, no hay nada que registrar
    IF NOT EXISTS (
        SELECT 1
        FROM inserted AS I
    )
    BEGIN
        RETURN;
    END;

    -- una fila por cada pedido insertado. Se trabaja sobre "inserted" completo
    -- porque un solo INSERT puede traer varios pedidos
    INSERT INTO dbo.HistorialEstadoPedido (
        IdPedido
        , IdEstadoPedido
        , IdUsuario
        , Comentario
    )
    SELECT I.IdPedido
        , I.IdEstadoPedido
        , I.IdUsuario -- el cliente que creó la orden
        , N'Orden creada por el cliente'
    FROM inserted AS I;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spActualizarCarrito.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spActualizarCarrito
    @inIdUsuario INT -- cliente dueño del carrito
    , @inIdCarritoDetalle INT -- línea del carrito que se cambia
    , @inCantidad INT -- nueva cantidad; 0 = quitar el producto del carrito
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP009 Modificar carrito (cambiar cantidad o quitar un producto).
El total se recalcula llamando después a spListarCarrito.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarCarrito
        @inIdUsuario = 2
        , @inIdCarritoDetalle = 1
        , @inCantidad = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @cantidadQuitar INT = 0;

        -- variables de uso general
        DECLARE @existencias INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @existencias = NULL;

        -- validaciones
        -- la línea debe existir y ser del cliente
        SELECT @existencias = PT.Cantidad
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        WHERE (CD.IdCarritoDetalle = @inIdCarritoDetalle)
            AND (CD.IdUsuario = @inIdUsuario);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50018; -- línea del carrito no existe
            RETURN;
        END;

        IF (@inCantidad IS NULL)
            OR (@inCantidad < @cantidadQuitar)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- GP009 restricción 1: no puede superar las existencias.
        -- quitar (0) siempre se permite, aunque el producto ya no exista
        IF (@inCantidad > @cantidadQuitar)
            AND (@inCantidad > @existencias)
        BEGIN
            SET @outResultCode = 50016; -- existencias insuficientes
            RETURN;
        END;

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tActualizarCarrito;

            DELETE FROM dbo.CarritoDetalle
            WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
                AND (@inCantidad = @cantidadQuitar);

            UPDATE dbo.CarritoDetalle
            SET Cantidad = @inCantidad
            WHERE (IdCarritoDetalle = @inIdCarritoDetalle)
                AND (@inCantidad > @cantidadQuitar);

        COMMIT TRANSACTION tActualizarCarrito;

        -- resultado para la capa lógica: indicador del carrito.
        -- 0 = el carrito quedó vacío (GP009 flujo alternativo)
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spActualizarDireccion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spActualizarDireccion
    @inIdUsuario INT -- cliente que edita (debe ser el dueño)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdDireccion INT -- dirección que se edita
    , @inIdProvincia INT -- nueva provincia
    , @inCanton NVARCHAR(64) -- nuevo cantón
    , @inDistrito NVARCHAR(64) -- nuevo distrito
    , @inOtrasSenas NVARCHAR(256) -- nuevas otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP005 Modificar dirección de envío.
Los pedidos ya hechos no cambian porque guardan una copia de la dirección
en texto (Pedido.DireccionEntrega).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdDireccion = 1
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'Higuito'
        , @inOtrasSenas = N'Frente a la plaza, portón negro'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionModificar INT = 8; -- TipoOperacion "Modificar dirección"

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = LTRIM(RTRIM(ISNULL(@inCanton, N'')));
        SET @distrito = LTRIM(RTRIM(ISNULL(@inDistrito, N'')));
        SET @otrasSenas = LTRIM(RTRIM(ISNULL(@inOtrasSenas, N'')));

        -- validaciones
        -- GP005 restricción 2: solo el dueño puede modificarla
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50014; -- dirección no existe o no es del cliente
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50013; -- provincia no existe
            RETURN;
        END;

        IF (@canton = N'')
            OR (@distrito = N'')
            OR (@otrasSenas = N'')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @huboCambio BIT
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @huboCambio = @false;

        SELECT @huboCambio = CASE
                WHEN (D.IdProvincia <> @inIdProvincia)
                    OR (D.Canton <> @canton)
                    OR (D.Distrito <> @distrito)
                    OR (D.OtrasSenas <> @otrasSenas)
                THEN @true
                ELSE @false
              END
        FROM dbo.Direccion AS D
        WHERE (D.IdDireccion = @inIdDireccion);

        -- si no cambió nada se sale con éxito y no se registra en bitácora
        IF (@huboCambio = @false)
        BEGIN
            RETURN;
        END;

        SET @jsonAntes = dbo.fnJsonDireccion(@inIdDireccion);

        -- transacción: cambio y bitácora van juntos
        BEGIN TRANSACTION tActualizarDireccion;

            UPDATE dbo.Direccion
            SET IdProvincia = @inIdProvincia
                , Canton = @canton
                , Distrito = @distrito
                , OtrasSenas = @otrasSenas
            WHERE (IdDireccion = @inIdDireccion);

            SET @jsonDespues = dbo.fnJsonDireccion(@inIdDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionModificar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarDireccion;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spActualizarDisponibilidad.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spActualizarDisponibilidad
    @inIdUsuario INT -- quién actualiza, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto
    , @inIdTalla INT -- talla que se ajusta
    , @inCantidad INT -- nueva cantidad disponible (entero >= 0)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI007 Actualizar disponibilidad del producto.
Si el producto todavía no tenía esa talla, se agrega; si ya la tenía, se
reemplaza la cantidad. Cantidad 0 = agotado en esa talla (GI007 postcondición 2).
El UPDATE bloquea la fila: si un cliente confirma una orden de esa misma
talla al mismo tiempo, una operación espera a la otra (GI007 restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarDisponibilidad
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inIdTalla = 4
        , @inCantidad = 3
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionDisponibilidad INT = 5; -- "Actualizar disponibilidad"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @cantidadActual INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @cantidadActual = NULL; -- NULL = el producto no tenía esa talla

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Talla AS T
            WHERE (T.IdTalla = @inIdTalla)
        )
        BEGIN
            SET @outResultCode = 50010; -- talla inválida
            RETURN;
        END;

        -- GI007 restricción 1: entero mayor o igual que cero
        IF (@inCantidad IS NULL)
            OR (@inCantidad < 0)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- preprocesamiento
        SELECT @cantidadActual = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        WHERE (PT.IdProducto = @inIdProducto)
            AND (PT.IdTalla = @inIdTalla);

        -- si la cantidad no cambia, éxito sin tocar nada
        IF (@cantidadActual = @inCantidad)
        BEGIN
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tActualizarDisponibilidad;

            -- la talla ya existía: se reemplaza la cantidad
            UPDATE dbo.ProductoTalla
            SET Cantidad = @inCantidad
            WHERE (IdProducto = @inIdProducto)
                AND (IdTalla = @inIdTalla);

            -- la talla no existía: se agrega
            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @inIdProducto
                , @inIdTalla
                , @inCantidad
            WHERE (@cantidadActual IS NULL);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionDisponibilidad
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarDisponibilidad;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spActualizarImagenProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spActualizarImagenProducto
    @inIdUsuario INT -- quién sube la foto, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto al que se asigna la foto
    , @inRutaImagen VARCHAR(260) -- ruta donde Node guardó el archivo
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI003 Subir foto del producto.
Node recibe el archivo, valida tamaño, lo guarda en disco y llama este SP
con la ruta. Aquí se valida otra vez la extensión (png o jpg).
Se devuelve la ruta anterior para que Node borre el archivo viejo.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarImagenProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inRutaImagen = 'uploads/productos/1_1731190000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionFoto INT = 6; -- TipoOperacion "Subir foto de producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @ruta VARCHAR(260)
            , @rutaAnterior VARCHAR(260);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @ruta = LOWER(LTRIM(RTRIM(ISNULL(@inRutaImagen, ''))));

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- GI003 restricción 1: solo png o jpg
        IF (@ruta NOT LIKE '%.png')
            AND (@ruta NOT LIKE '%.jpg')
            AND (@ruta NOT LIKE '%.jpeg')
        BEGIN
            SET @outResultCode = 50012; -- formato de imagen no permitido
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SELECT @rutaAnterior = P.RutaImagen
        FROM dbo.Producto AS P
        WHERE (P.IdProducto = @inIdProducto);

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción: foto y bitácora van juntas
        BEGIN TRANSACTION tActualizarImagenProducto;

            UPDATE dbo.Producto
            SET RutaImagen = @ruta
            WHERE (IdProducto = @inIdProducto);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionFoto
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarImagenProducto;

        -- resultado para la capa lógica: archivo viejo que puede borrar
        SELECT @rutaAnterior AS RutaAnterior;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spActualizarProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spActualizarProducto
    @inIdUsuario INT -- quién edita, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto que se edita
    , @inIdCategoria INT -- nueva categoría
    , @inNombre NVARCHAR(100) -- nuevo nombre
    , @inDescripcion NVARCHAR(500) -- nueva descripción (opcional)
    , @inPrecio MONEY -- nuevo precio
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI005 Modificar producto.
Las existencias por talla se cambian con spActualizarDisponibilidad (GI007).
El UPDATE es atómico: si un cliente confirma una orden al mismo tiempo, una
de las dos operaciones espera a que la otra termine (GI005 restricción 2).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @inIdCategoria = 1
        , @inNombre = N'Blusa floreada manga corta'
        , @inDescripcion = N'Blusa de algodón con estampado de flores'
        , @inPrecio = 13000
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionModificar INT = 3; -- TipoOperacion "Modificar producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @descripcion = NULLIF(LTRIM(RTRIM(@inDescripcion)), '');

        -- validaciones de acceso
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- el producto debe existir y no estar eliminado
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- validaciones de campos (las mismas que al agregar)
        IF (@nombre = '')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categoria AS C
            WHERE (C.IdCategoria = @inIdCategoria)
        )
        BEGIN
            SET @outResultCode = 50007; -- categoría no existe
            RETURN;
        END;

        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50008; -- precio inválido
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @huboCambio BIT
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento: compara lo recibido contra lo guardado.
        -- ISNULL evita que una descripción NULL esconda el cambio
        SET @huboCambio = @false;

        SELECT @huboCambio = CASE
                WHEN (P.IdCategoria <> @inIdCategoria)
                    OR (P.Nombre <> @nombre)
                    OR (ISNULL(P.Descripcion, N'') <> ISNULL(@descripcion, N''))
                    OR (P.Precio <> @inPrecio)
                THEN @true
                ELSE @false
              END
        FROM dbo.Producto AS P
        WHERE (P.IdProducto = @inIdProducto);

        -- si no cambió nada se sale con éxito y no se registra en bitácora
        IF (@huboCambio = @false)
        BEGIN
            RETURN;
        END;

        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción: cambio y bitácora van juntos
        BEGIN TRANSACTION tActualizarProducto;

            UPDATE dbo.Producto
            SET IdCategoria = @inIdCategoria
                , Nombre = @nombre
                , Descripcion = @descripcion
                , Precio = @inPrecio
            WHERE (IdProducto = @inIdProducto);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionModificar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarProducto;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spAgregarCarrito.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spAgregarCarrito
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdProductoTalla INT -- producto y talla elegidos
    , @inCantidad INT -- cantidad a agregar (entero > 0)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP007 Agregar productos al carrito.
No reserva existencias (restricción 3): eso se garantiza en spConfirmarOrden.
Si el producto y la talla ya estaban en el carrito, se suma la cantidad
sin superar las existencias (flujo alternativo).
Devuelve el total de artículos para el indicador del carrito.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarCarrito
        @inIdUsuario = 2
        , @inIdProductoTalla = 1
        , @inCantidad = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @existencias INT
            , @enCarrito INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @existencias = NULL;
        SET @enCarrito = 0;

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        -- GP007 restricción 2: entero positivo
        IF (@inCantidad IS NULL)
            OR (@inCantidad <= 0)
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- la talla debe existir y su producto no estar eliminado
        SELECT @existencias = PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        WHERE (PT.IdProductoTalla = @inIdProductoTalla)
            AND (P.FlagActivo = @true);

        IF (@existencias IS NULL)
        BEGIN
            SET @outResultCode = 50015; -- producto o talla no existe
            RETURN;
        END;

        -- lo que ya tenía en el carrito de esa talla
        SELECT @enCarrito = CD.Cantidad
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario)
            AND (CD.IdProductoTalla = @inIdProductoTalla);

        -- no puede pedir más de lo que hay (incluye agotados: existencias 0)
        IF ((@enCarrito + @inCantidad) > @existencias)
        BEGIN
            SET @outResultCode = 50016; -- existencias insuficientes
            RETURN;
        END;

        -- transacción. Sin IF: el WHERE de cada sentencia decide cuál aplica
        BEGIN TRANSACTION tAgregarCarrito;

            -- ya estaba en el carrito: se suma
            UPDATE dbo.CarritoDetalle
            SET Cantidad = Cantidad + @inCantidad
            WHERE (IdUsuario = @inIdUsuario)
                AND (IdProductoTalla = @inIdProductoTalla);

            -- no estaba: se agrega
            INSERT INTO dbo.CarritoDetalle (
                IdUsuario
                , IdProductoTalla
                , Cantidad
            )
            SELECT @inIdUsuario
                , @inIdProductoTalla
                , @inCantidad
            WHERE (@enCarrito = 0);

        COMMIT TRANSACTION tAgregarCarrito;

        -- resultado para la capa lógica: indicador del carrito
        SELECT ISNULL(SUM(CD.Cantidad), 0) AS CantidadArticulos
        FROM dbo.CarritoDetalle AS CD
        WHERE (CD.IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spAgregarDireccion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spAgregarDireccion
    @inIdUsuario INT -- cliente dueño de la dirección
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProvincia INT -- provincia
    , @inCanton NVARCHAR(64) -- cantón
    , @inDistrito NVARCHAR(64) -- distrito
    , @inOtrasSenas NVARCHAR(256) -- otras señas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP004 Agregar dirección de envío.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdProvincia = 1
        , @inCanton = N'Desamparados'
        , @inDistrito = N'San Miguel'
        , @inOtrasSenas = N'200 m sur de la iglesia, casa verde'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @tipoOperacionAgregar INT = 7; -- TipoOperacion "Agregar dirección"

        -- variables de uso general
        DECLARE @canton NVARCHAR(64)
            , @distrito NVARCHAR(64)
            , @otrasSenas NVARCHAR(256);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @canton = LTRIM(RTRIM(ISNULL(@inCanton, N'')));
        SET @distrito = LTRIM(RTRIM(ISNULL(@inDistrito, N'')));
        SET @otrasSenas = LTRIM(RTRIM(ISNULL(@inOtrasSenas, N'')));

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Provincia AS PR
            WHERE (PR.IdProvincia = @inIdProvincia)
        )
        BEGIN
            SET @outResultCode = 50013; -- provincia no existe
            RETURN;
        END;

        -- GP004 restricción 1: todos los campos son obligatorios
        IF (@canton = N'')
            OR (@distrito = N'')
            OR (@otrasSenas = N'')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idDireccion INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: dirección y bitácora van juntas
        BEGIN TRANSACTION tAgregarDireccion;

            INSERT INTO dbo.Direccion (
                IdUsuario
                , IdProvincia
                , Canton
                , Distrito
                , OtrasSenas
            )
            VALUES (
                @inIdUsuario
                , @inIdProvincia
                , @canton
                , @distrito
                , @otrasSenas
            );

            SET @idDireccion = SCOPE_IDENTITY();
            SET @jsonDespues = dbo.fnJsonDireccion(@idDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionAgregar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tAgregarDireccion;

        -- resultado para la capa lógica (GP012 la puede preseleccionar)
        SELECT @idDireccion AS IdDireccion;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spAgregarProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spAgregarProducto
    @inIdUsuario INT -- quién agrega, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdCategoria INT -- categoría de la prenda
    , @inNombre NVARCHAR(100) -- nombre del producto
    , @inDescripcion NVARCHAR(500) -- descripción (opcional)
    , @inPrecio MONEY -- precio en colones, mayor a 0
    , @inTallasJson NVARCHAR(MAX) -- tallas y existencias: [{"IdTalla":2,"Cantidad":1}, ...]
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI002 Agregar producto.
La foto se sube después con spActualizarImagenProducto (GI003), por eso
se devuelve el IdProducto creado.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdCategoria = 1
        , @inNombre = N'Blusa floreada'
        , @inDescripcion = N'Blusa de algodón con estampado de flores'
        , @inPrecio = 12500
        , @inTallasJson = N'[{"IdTalla":2,"Cantidad":1},{"IdTalla":3,"Cantidad":2}]'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionAgregar INT = 2; -- TipoOperacion "Agregar producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500)
            , @tallasJson NVARCHAR(MAX);

        -- tallas recibidas, ya separadas del JSON
        DECLARE @tallas TABLE (
            IdTalla INT NULL
            , Cantidad INT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @descripcion = NULLIF(LTRIM(RTRIM(@inDescripcion)), ''); -- vacía = NULL
        SET @tallasJson = LTRIM(RTRIM(ISNULL(@inTallasJson, '')));

        -- validaciones de acceso
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- validaciones de campos
        IF (@nombre = '')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categoria AS C
            WHERE (C.IdCategoria = @inIdCategoria)
        )
        BEGIN
            SET @outResultCode = 50007; -- categoría no existe
            RETURN;
        END;

        -- GI002 restricción 1: precio positivo
        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50008; -- precio inválido
            RETURN;
        END;

        -- el JSON de tallas debe ser un arreglo válido
        IF (ISNULL(ISJSON(@tallasJson), 0) = 0)
            OR (LEFT(@tallasJson, 1) <> '[')
        BEGIN
            SET @outResultCode = 50010; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: se separa el JSON en filas
        INSERT INTO @tallas (
            IdTalla
            , Cantidad
        )
        SELECT J.IdTalla
            , J.Cantidad
        FROM OPENJSON(@tallasJson)
        WITH (
            IdTalla INT '$.IdTalla'
            , Cantidad INT '$.Cantidad'
        ) AS J;

        -- al menos una talla, todas existentes en el catálogo y sin repetir
        IF NOT EXISTS (
                SELECT 1
                FROM @tallas
            )
            OR EXISTS (
                SELECT 1
                FROM @tallas AS TA
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM dbo.Talla AS T
                    WHERE (T.IdTalla = TA.IdTalla)
                )
            )
            OR (
                SELECT COUNT(DISTINCT TA.IdTalla)
                FROM @tallas AS TA
            ) <> (
                SELECT COUNT(1)
                FROM @tallas
            )
        BEGIN
            SET @outResultCode = 50010; -- lista de tallas inválida
            RETURN;
        END;

        -- GI002 restricción 1: cantidad entera y no negativa
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad IS NULL)
                OR (TA.Cantidad < 0)
        )
        BEGIN
            SET @outResultCode = 50009; -- cantidad inválida
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idProducto INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: producto, tallas y bitácora se guardan juntos o nada
        BEGIN TRANSACTION tAgregarProducto;

            INSERT INTO dbo.Producto (
                IdCategoria
                , Nombre
                , Descripcion
                , Precio
            )
            VALUES (
                @inIdCategoria
                , @nombre
                , @descripcion
                , @inPrecio
            );

            SET @idProducto = SCOPE_IDENTITY();

            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @idProducto
                , TA.IdTalla
                , TA.Cantidad
            FROM @tallas AS TA;

            -- el JSON se arma después de insertar para que lleve el Id y las tallas
            SET @jsonDespues = dbo.fnJsonProducto(@idProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionAgregar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tAgregarProducto;

        -- resultado para la capa lógica: con este Id se sube la foto
        SELECT @idProducto AS IdProducto;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spCambiarEstadoPedido.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spCambiarEstadoPedido
    @inIdUsuario INT -- quién cambia el estado, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdPedido INT -- pedido
    , @inIdEstadoNuevo INT -- estado al que pasa
    , @inMotivo NVARCHAR(300) -- obligatorio para Rechazado y Cancelado
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP016 Confirmar o rechazar pedido, GP017 Actualizar estado de pedido y
GP019 Notificar al cliente.

Un solo SP para todos los cambios de estado porque las reglas vienen de
las tablas de catálogo, no del código:
    - TransicionEstadoPedido dice a qué estado se puede pasar (solo avanzan)
    - EstadoPedido.FlagRequiereMotivo pide el motivo (Rechazado, Cancelado)
    - EstadoPedido.FlagDevuelveInventario regresa las existencias

La notificación queda en la tabla Notificacion; el backend la envía por
correo y la marca con spMarcarNotificacion.

Ejemplo de ejecución (confirmar):
    DECLARE @resultado INT;

    EXEC dbo.spCambiarEstadoPedido
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdPedido = 1
        , @inIdEstadoNuevo = 2
        , @inMotivo = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEstado INT = 11; -- "Cambiar estado de pedido"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idEstadoActual INT
            , @idCliente INT
            , @requiereDireccion BIT
            , @requiereMotivo BIT
            , @devuelveInventario BIT
            , @transicionValida BIT
            , @motivo NVARCHAR(300);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idEstadoActual = NULL;
        SET @requiereMotivo = NULL;
        SET @transicionValida = @false;
        SET @motivo = NULLIF(LTRIM(RTRIM(@inMotivo)), N'');

        -- validaciones
        -- GP016 restricción 1: solo la administradora
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        SELECT @idEstadoActual = P.IdEstadoPedido
            , @idCliente = P.IdUsuario
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        IF (@idEstadoActual IS NULL)
        BEGIN
            SET @outResultCode = 50024; -- pedido no existe
            RETURN;
        END;

        SELECT @requiereMotivo = EP.FlagRequiereMotivo
            , @devuelveInventario = EP.FlagDevuelveInventario
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        -- GP017 restricción 2: la transición debe estar permitida para el
        -- estado actual y para el tipo de entrega (envío o retiro)
        SELECT @transicionValida = @true
        FROM dbo.TransicionEstadoPedido AS TEP
        WHERE (TEP.IdEstadoActual = @idEstadoActual)
            AND (TEP.IdEstadoNuevo = @inIdEstadoNuevo)
            AND (
                (TEP.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TEP.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            );

        IF (@requiereMotivo IS NULL)
            OR (@transicionValida = @false)
        BEGIN
            SET @outResultCode = 50025; -- transición de estado no permitida
            RETURN;
        END;

        -- GP016 restricción 3: rechazar (y cancelar) exige motivo
        IF (@requiereMotivo = @true)
            AND (@motivo IS NULL)
        BEGIN
            SET @outResultCode = 50026; -- falta el motivo
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @nombreEstadoActual NVARCHAR(32)
            , @nombreEstadoNuevo NVARCHAR(32)
            , @nombreCliente NVARCHAR(100)
            , @correoCliente VARCHAR(128)
            , @asunto NVARCHAR(128)
            , @mensaje NVARCHAR(600)
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SELECT @nombreEstadoActual = EP.Nombre
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @idEstadoActual);

        SELECT @nombreEstadoNuevo = EP.Nombre
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        SELECT @nombreCliente = U.Nombre
            , @correoCliente = U.Correo
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @idCliente);

        -- GP019 restricción 1: número de pedido, nuevo estado y motivo si aplica.
        -- restricción 3: sin datos sensibles
        SET @asunto = CONCAT(N'Pedido #', @inIdPedido, N': ', @nombreEstadoNuevo);
        SET @mensaje = LEFT(CONCAT(
                N'Hola ', @nombreCliente
                , N'. Su pedido #', @inIdPedido
                , N' cambió al estado "', @nombreEstadoNuevo, N'".'
                , CASE
                    WHEN (@motivo IS NOT NULL) THEN CONCAT(N' Motivo: ', @motivo)
                    ELSE N''
                  END
                , N' Gracias por comprar en Confecciones Capanni.'
            ), 600);

        SET @jsonAntes = (
            SELECT @inIdPedido AS IdPedido
                , @nombreEstadoActual AS Estado
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        SET @jsonDespues = (
            SELECT @inIdPedido AS IdPedido
                , @nombreEstadoNuevo AS Estado
                , @motivo AS Motivo
                , @devuelveInventario AS DevuelveInventario
            FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
        );

        -- transacción: estado, inventario, historial, notificación y
        -- bitácora se guardan juntos o nada
        BEGIN TRANSACTION tCambiarEstadoPedido;

            -- el WHERE con el estado actual evita aplicar dos veces el mismo
            -- cambio (por ejemplo, doble clic en "Rechazar", que devolvería
            -- el inventario dos veces)
            UPDATE dbo.Pedido
            SET IdEstadoPedido = @inIdEstadoNuevo
                , MotivoEstado = CASE
                    WHEN (@motivo IS NOT NULL) THEN @motivo
                    ELSE MotivoEstado
                  END
            WHERE (IdPedido = @inIdPedido)
                AND (IdEstadoPedido = @idEstadoActual);

            IF (@@ROWCOUNT = 0)
            BEGIN
                ROLLBACK TRANSACTION tCambiarEstadoPedido;
                SET @outResultCode = 50025; -- otro proceso ya cambió el estado
                RETURN;
            END;

            -- Rechazado o Cancelado: regresan las existencias (GP016 alterno,
            -- GP017 restricción 3). Sin IF: el WHERE decide
            UPDATE PT
            SET Cantidad = PT.Cantidad + PD.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN dbo.PedidoDetalle AS PD
                ON (PD.IdProductoTalla = PT.IdProductoTalla)
            WHERE (PD.IdPedido = @inIdPedido)
                AND (@devuelveInventario = @true);

            -- historial con fecha y hora (GP016 paso 2.1, GP017 paso 4.1)
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
            )
            VALUES (
                @inIdPedido
                , @inIdEstadoNuevo
                , @inIdUsuario
                , @motivo
            );

            -- notificación pendiente de envío (GP019)
            INSERT INTO dbo.Notificacion (
                IdPedido
                , Correo
                , Asunto
                , Mensaje
            )
            VALUES (
                @inIdPedido
                , @correoCliente
                , @asunto
                , @mensaje
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEstado
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tCambiarEstadoPedido;

        -- resultado para la capa lógica: a quién avisar en tiempo real y si
        -- el catálogo cambió (cuando se devuelven existencias)
        SELECT @idCliente AS IdUsuarioCliente
            , @nombreEstadoNuevo AS Estado
            , @devuelveInventario AS DevuelveInventario;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spConfirmarOrden.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spConfirmarOrden
    @inIdUsuario INT -- cliente que confirma
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdMetodoPago INT -- SINPE Móvil o efectivo (GP011)
    , @inIdMetodoEntrega INT -- método de entrega (GP012)
    , @inIdDireccion INT -- dirección guardada; NULL si es retiro en el taller
    , @inRutaComprobante VARCHAR(260) -- imagen del comprobante SINPE; NULL si es efectivo
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP014 Confirmar orden de compra (incluye GP011, GP012, GP013 y GP020).
Es el SP más importante del proyecto: aquí se cumplen las propiedades ACID
que pide la ERS (sección 2.4 y acuerdo 2 de la minuta #1).

Cómo se evita vender dos veces una pieza única:
    Dentro de la transacción se leen las existencias de los productos del
    carrito con WITH (UPDLOCK, HOLDLOCK). Ese bloqueo dura hasta el COMMIT.
    Si otro cliente confirma al mismo tiempo una orden con la misma talla,
    su SP se queda esperando en esa lectura; cuando el primero termina, el
    segundo ve las existencias ya descontadas y recibe 50016.
    Resultado: se vende al primero que confirma (minuta #1, tema 2).

Si algún producto ya no está disponible no se registra nada (ni pedido ni
descuento) y se devuelve la lista de productos que fallaron (flujo
alternativo de GP014).

Resultado si todo sale bien: número de pedido y montos.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConfirmarOrden
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdMetodoPago = 1
        , @inIdMetodoEntrega = 1
        , @inIdDireccion = 1
        , @inRutaComprobante = 'uploads/comprobantes/2_1731190000.jpg'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1 -- "Pendiente de confirmación"
            , @tipoOperacionConfirmar INT = 10; -- "Confirmar orden de compra"

        -- variables de uso general
        DECLARE @requiereComprobante BIT
            , @soloRetiro BIT
            , @requiereDireccion BIT
            , @costoEnvio MONEY
            , @direccionTexto NVARCHAR(400)
            , @rutaComprobante VARCHAR(260);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @requiereComprobante = NULL; -- NULL = método de pago no existe
        SET @requiereDireccion = NULL; -- NULL = método de entrega no existe
        SET @direccionTexto = NULL;
        SET @rutaComprobante = LOWER(NULLIF(LTRIM(RTRIM(@inRutaComprobante)), ''));

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        -- GP014 precondición 2: carrito con al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50017; -- carrito vacío
            RETURN;
        END;

        -- método de pago
        SELECT @requiereComprobante = MP.FlagRequiereComprobante
            , @soloRetiro = MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        WHERE (MP.IdMetodoPago = @inIdMetodoPago);

        IF (@requiereComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50019; -- método de pago no existe
            RETURN;
        END;

        -- método de entrega
        SELECT @requiereDireccion = ME.FlagRequiereDireccion
            , @costoEnvio = ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        IF (@requiereDireccion IS NULL)
        BEGIN
            SET @outResultCode = 50020; -- método de entrega no existe
            RETURN;
        END;

        -- GP011 restricción 2: efectivo solo con retiro en el taller
        IF (@soloRetiro = @true)
            AND (@requiereDireccion = @true)
        BEGIN
            SET @outResultCode = 50021; -- efectivo solo para retiro en el taller
            RETURN;
        END;

        -- GP012 restricción 2: los métodos con envío necesitan una dirección
        -- activa del propio cliente. Se copia como texto al pedido
        IF (@requiereDireccion = @true)
        BEGIN
            SELECT @direccionTexto = CONCAT(
                    D.OtrasSenas, N', ', D.Distrito, N', ', D.Canton, N', ', PR.Nombre
                )
            FROM dbo.Direccion AS D
            INNER JOIN dbo.Provincia AS PR
                ON (PR.IdProvincia = D.IdProvincia)
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true);

            IF (@direccionTexto IS NULL)
            BEGIN
                SET @outResultCode = 50022; -- falta una dirección válida
                RETURN;
            END;
        END;

        -- GP013 restricción 2: SINPE requiere comprobante
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante IS NULL)
        BEGIN
            SET @outResultCode = 50023; -- falta el comprobante
            RETURN;
        END;

        -- GP013 restricción 1: png o jpg
        IF (@requiereComprobante = @true)
            AND (@rutaComprobante NOT LIKE '%.png')
            AND (@rutaComprobante NOT LIKE '%.jpg')
            AND (@rutaComprobante NOT LIKE '%.jpeg')
        BEGIN
            SET @outResultCode = 50012; -- formato de imagen no permitido
            RETURN;
        END;

        -- si paga en efectivo no se guarda comprobante aunque venga uno
        SET @rutaComprobante = CASE
                WHEN (@requiereComprobante = @true) THEN @rutaComprobante
                ELSE NULL
            END;

        -- variables para la transacción
        DECLARE @cantidadLineas INT
            , @subtotal MONEY
            , @total MONEY
            , @idPedido INT
            , @jsonDespues NVARCHAR(MAX);

        -- productos del carrito que ya no se pueden vender
        DECLARE @noDisponibles TABLE (
            IdCarritoDetalle INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , Talla NVARCHAR(16) NOT NULL
            , CantidadSolicitada INT NOT NULL
            , CantidadDisponible INT NOT NULL
        );

        -- transacción: verificar existencias, descontarlas, crear el pedido,
        -- guardar el comprobante y vaciar el carrito es UNA sola operación
        BEGIN TRANSACTION tConfirmarOrden;

            -- 1. bloquea las existencias de todo lo que hay en el carrito.
            -- UPDLOCK: nadie más puede tomar estas filas para modificarlas.
            -- HOLDLOCK: el bloqueo se mantiene hasta el COMMIT o ROLLBACK
            SELECT @cantidadLineas = COUNT(1)
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT WITH (UPDLOCK, HOLDLOCK)
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 2. con las filas bloqueadas, revisa qué ya no está disponible
            -- (producto eliminado o existencias menores a lo pedido)
            INSERT INTO @noDisponibles (
                IdCarritoDetalle
                , NombreProducto
                , Talla
                , CantidadSolicitada
                , CantidadDisponible
            )
            SELECT CD.IdCarritoDetalle
                , P.Nombre
                , T.Nombre
                , CD.Cantidad
                , CASE
                    WHEN (P.FlagActivo = @true) THEN PT.Cantidad
                    ELSE 0
                  END
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario)
                AND (
                    (P.FlagActivo = @false)
                    OR (PT.Cantidad < CD.Cantidad)
                );

            -- si algo falló no se registra nada: se deshace y se informa cuáles
            IF EXISTS (
                SELECT 1
                FROM @noDisponibles
            )
            BEGIN
                ROLLBACK TRANSACTION tConfirmarOrden;

                -- la variable tabla no se pierde con el ROLLBACK
                SELECT ND.IdCarritoDetalle
                    , ND.NombreProducto
                    , ND.Talla
                    , ND.CantidadSolicitada
                    , ND.CantidadDisponible
                FROM @noDisponibles AS ND;

                SET @outResultCode = 50016; -- existencias insuficientes
                RETURN;
            END;

            -- 3. montos con el precio vigente (GP020)
            SELECT @subtotal = SUM(P.Precio * CD.Cantidad)
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            WHERE (CD.IdUsuario = @inIdUsuario);

            SET @total = @subtotal + ISNULL(@costoEnvio, 0); -- NULL = envío a coordinar

            -- 4. el pedido. El trigger trPedidoPrimerEstado agrega su primer
            -- registro en HistorialEstadoPedido
            INSERT INTO dbo.Pedido (
                IdUsuario
                , IdEstadoPedido
                , IdMetodoPago
                , IdMetodoEntrega
                , DireccionEntrega
                , SubtotalProductos
                , CostoEnvio
                , Total
            )
            VALUES (
                @inIdUsuario
                , @estadoPendiente
                , @inIdMetodoPago
                , @inIdMetodoEntrega
                , @direccionTexto
                , @subtotal
                , @costoEnvio
                , @total
            );

            -- SCOPE_IDENTITY (y no @@IDENTITY) para no tomar el id que
            -- generó el trigger en HistorialEstadoPedido
            SET @idPedido = SCOPE_IDENTITY();

            -- 5. detalle con copia de nombre, talla y precio (sección 2.4)
            INSERT INTO dbo.PedidoDetalle (
                IdPedido
                , IdProductoTalla
                , NombreProducto
                , NombreTalla
                , PrecioUnitario
                , Cantidad
                , Subtotal
            )
            SELECT @idPedido
                , CD.IdProductoTalla
                , P.Nombre
                , T.Nombre
                , P.Precio
                , CD.Cantidad
                , P.Precio * CD.Cantidad
            FROM dbo.CarritoDetalle AS CD
            INNER JOIN dbo.ProductoTalla AS PT
                ON (PT.IdProductoTalla = CD.IdProductoTalla)
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            INNER JOIN dbo.Talla AS T
                ON (T.IdTalla = PT.IdTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 6. descuenta las existencias (GP014 postcondición 2)
            UPDATE PT
            SET Cantidad = PT.Cantidad - CD.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN dbo.CarritoDetalle AS CD
                ON (CD.IdProductoTalla = PT.IdProductoTalla)
            WHERE (CD.IdUsuario = @inIdUsuario);

            -- 7. comprobante, solo si es SINPE. Sin IF: el WHERE decide
            INSERT INTO dbo.Comprobante (
                IdPedido
                , RutaArchivo
            )
            SELECT @idPedido
                , @rutaComprobante
            WHERE (@rutaComprobante IS NOT NULL);

            -- 8. vacía el carrito (GP014 paso 2.4)
            DELETE FROM dbo.CarritoDetalle
            WHERE (IdUsuario = @inIdUsuario);

            -- 9. bitácora con el pedido completo
            SET @jsonDespues = (
                SELECT P.IdPedido
                    , MP.Nombre AS MetodoPago
                    , ME.Nombre AS MetodoEntrega
                    , P.DireccionEntrega
                    , P.SubtotalProductos
                    , P.CostoEnvio
                    , P.Total
                    , (
                        SELECT PD.NombreProducto
                            , PD.NombreTalla
                            , PD.Cantidad
                            , PD.PrecioUnitario
                        FROM dbo.PedidoDetalle AS PD
                        WHERE (PD.IdPedido = P.IdPedido)
                        FOR JSON PATH
                      ) AS Productos
                FROM dbo.Pedido AS P
                INNER JOIN dbo.MetodoPago AS MP
                    ON (MP.IdMetodoPago = P.IdMetodoPago)
                INNER JOIN dbo.MetodoEntrega AS ME
                    ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
                WHERE (P.IdPedido = @idPedido)
                FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionConfirmar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tConfirmarOrden;

        -- resultado para la capa lógica (GP014 criterio 3: número de pedido)
        SELECT @idPedido AS IdPedido
            , @subtotal AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @total AS Total;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace todo
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spEliminarDireccion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spEliminarDireccion
    @inIdUsuario INT -- cliente que elimina (debe ser el dueño)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdDireccion INT -- dirección que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP006 Eliminar dirección de envío.
Eliminación lógica: deja de mostrarse y de ofrecerse al elegir el método
de entrega (criterio 2). La confirmación la hace el frontend.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarDireccion
        @inIdUsuario = 2
        , @inIP = '127.0.0.1'
        , @inIdDireccion = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEliminar INT = 9; -- TipoOperacion "Eliminar dirección"

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: debe existir, estar activa y ser del cliente
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50014; -- dirección no existe o no es del cliente
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @jsonAntes = dbo.fnJsonDireccion(@inIdDireccion);

        -- transacción: eliminación lógica y bitácora van juntas
        BEGIN TRANSACTION tEliminarDireccion;

            UPDATE dbo.Direccion
            SET FlagActivo = @false
            WHERE (IdDireccion = @inIdDireccion);

            SET @jsonDespues = dbo.fnJsonDireccion(@inIdDireccion);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEliminar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tEliminarDireccion;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spEliminarProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spEliminarProducto
    @inIdUsuario INT -- quién elimina, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdProducto INT -- producto que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI006 Eliminar producto.
Es una eliminación LÓGICA (FlagActivo = 0): el historial de ventas debe ser
inmutable (sección 2.4 de la ERS), así que un producto que ya se vendió no
puede borrarse físicamente. Para la clienta el efecto es el mismo: deja de
verse en el inventario y en el catálogo (GI006 criterio 2).
La confirmación "¿Confirma que desea eliminar...?" la hace el frontend.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarProducto
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdProducto = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEliminar INT = 4; -- TipoOperacion "Eliminar producto"

        -- variables de uso general
        DECLARE @esAdministrador BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o ya fue eliminado
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @fechaDesactivacion DATETIME
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @fechaDesactivacion = GETDATE();
        SET @jsonAntes = dbo.fnJsonProducto(@inIdProducto);

        -- transacción: la eliminación lógica y la bitácora van juntas.
        -- las líneas de carrito con este producto se dejan: el carrito las
        -- muestra como "No disponible" (GP008 flujo alternativo)
        BEGIN TRANSACTION tEliminarProducto;

            UPDATE dbo.Producto
            SET FlagActivo = @false
                , FechaDesactivacion = @fechaDesactivacion
            WHERE (IdProducto = @inIdProducto);

            SET @jsonDespues = dbo.fnJsonProducto(@inIdProducto);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEliminar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tEliminarProducto;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spHistorialVentas.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spHistorialVentas
    @inIdUsuario INT -- quién consulta, debe ser administradora
    , @inFechaInicio DATE -- desde (NULL = sin límite)
    , @inFechaFin DATE -- hasta, inclusive (NULL = sin límite)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI009 Historial de productos vendidos.
Cuenta como venta todo pedido que la administradora ya confirmó y que no
terminó rechazado ni cancelado (criterio 1: "órdenes completadas").
Es solo lectura: no hay SP para modificar ni borrar este historial
(restricción 2), porque sale de PedidoDetalle, que nunca se edita.

Devuelve dos resultados:
    1. detalle de productos vendidos
    2. resumen: cantidad de prendas y monto total

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spHistorialVentas
        @inIdUsuario = 1
        , @inFechaInicio = NULL
        , @inFechaFin = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @estadoPendiente INT = 1;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @fechaFinExclusiva DATE;

        -- ventas que cumplen los filtros
        DECLARE @ventas TABLE (
            IdPedidoDetalle INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        -- FechaCreacion tiene hora: se compara contra el día siguiente
        SET @fechaFinExclusiva = DATEADD(DAY, 1, @inFechaFin);

        -- validaciones: restricción 1, solo administración
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- preprocesamiento
        INSERT INTO @ventas (
            IdPedidoDetalle
        )
        SELECT PD.IdPedidoDetalle
        FROM dbo.PedidoDetalle AS PD
        INNER JOIN dbo.Pedido AS P
            ON (P.IdPedido = PD.IdPedido)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        WHERE (P.IdEstadoPedido <> @estadoPendiente)
            AND (EP.FlagDevuelveInventario = @false) -- excluye rechazados y cancelados
            AND (
                (@inFechaInicio IS NULL)
                OR (P.FechaCreacion >= @inFechaInicio)
            )
            AND (
                (@inFechaFin IS NULL)
                OR (P.FechaCreacion < @fechaFinExclusiva)
            );

        -- primer resultado: detalle
        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , PD.NombreProducto
            , PD.NombreTalla
            , PD.Cantidad
            , PD.PrecioUnitario
            , PD.Subtotal
            , EP.Nombre AS Estado
        FROM @ventas AS V
        INNER JOIN dbo.PedidoDetalle AS PD
            ON (PD.IdPedidoDetalle = V.IdPedidoDetalle)
        INNER JOIN dbo.Pedido AS P
            ON (P.IdPedido = PD.IdPedido)
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        ORDER BY P.FechaCreacion DESC
            , PD.IdPedidoDetalle;

        -- segundo resultado: resumen
        SELECT ISNULL(SUM(PD.Cantidad), 0) AS PrendasVendidas
            , ISNULL(SUM(PD.Subtotal), 0) AS MontoVendido
        FROM @ventas AS V
        INNER JOIN dbo.PedidoDetalle AS PD
            ON (PD.IdPedidoDetalle = V.IdPedidoDetalle);

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spLimpiarBD.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spLimpiarBD
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Borra todos los datos de prueba (productos, clientes, carritos, pedidos y
bitácora) y deja los catálogos y la cuenta de la administradora.
Sirve para dejar la base limpia antes de la presentación.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spLimpiarBD
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- transacción: se vacía todo o no se toca nada
        BEGIN TRANSACTION tLimpiarBD;

            -- se borra en orden inverso a las llaves foráneas:
            -- primero las tablas hijas y al final las referenciadas (padres)
            DELETE FROM dbo.Notificacion; -- depende de Pedido
            DELETE FROM dbo.HistorialEstadoPedido; -- depende de Pedido y Usuario
            DELETE FROM dbo.Comprobante; -- depende de Pedido
            DELETE FROM dbo.PedidoDetalle; -- depende de Pedido y ProductoTalla
            DELETE FROM dbo.Pedido; -- depende de Usuario
            DELETE FROM dbo.CarritoDetalle; -- depende de Usuario y ProductoTalla
            DELETE FROM dbo.ProductoTalla; -- depende de Producto
            DELETE FROM dbo.Producto;
            DELETE FROM dbo.Direccion; -- depende de Usuario
            DELETE FROM dbo.Bitacora; -- depende de Usuario
            DELETE FROM dbo.Usuario
            WHERE (EsAdministrador = @false); -- la administradora se conserva

            -- reinicia los IDENTITY para que los ids vuelvan a empezar en 1.
            -- solo las tablas que ya tuvieron filas: en una tabla recién
            -- creada, RESEED 0 haría que el primer id fuera 0.
            -- Usuario no se reinicia porque la administradora sigue ahí
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Notificacion')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Notificacion', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.HistorialEstadoPedido')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.HistorialEstadoPedido', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Comprobante')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Comprobante', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.PedidoDetalle')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.PedidoDetalle', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Pedido')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Pedido', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.CarritoDetalle')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.CarritoDetalle', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.ProductoTalla')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.ProductoTalla', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Producto')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Producto', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Direccion')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Direccion', RESEED, 0) WITH NO_INFOMSGS;
            IF EXISTS (SELECT 1 FROM sys.identity_columns AS IC WHERE (IC.object_id = OBJECT_ID('dbo.Bitacora')) AND (IC.last_value IS NOT NULL))
                DBCC CHECKIDENT ('dbo.Bitacora', RESEED, 0) WITH NO_INFOMSGS;

        COMMIT TRANSACTION tLimpiarBD;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarCarrito.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarCarrito
    @inIdUsuario INT -- cliente dueño del carrito
    , @inIdMetodoEntrega INT -- método de entrega elegido (NULL = aún no elige)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP008 Visualizar carrito y GP020 Calcular costo del pedido.
Se llama al abrir el carrito, después de cada cambio (GP009) y al elegir
el método de entrega (GP012), así el total siempre está recalculado.

Devuelve dos resultados:
    1. líneas del carrito; Disponible = 0 si el producto se eliminó o ya no
       hay existencias suficientes (GP008 restricción 3)
    2. resumen: subtotal (solo líneas disponibles), envío y total

Costo = suma(precio unitario x cantidad) + envío (GP020 restricción 1).
CostoEnvio NULL con EnvioACoordinar = 1 -> "Envío a coordinar con la
administradora" (GP020 flujo alternativo).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarCarrito
        @inIdUsuario = 2
        , @inIdMetodoEntrega = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @costoEnvio MONEY
            , @envioACoordinar BIT;

        -- líneas del carrito ya calculadas
        DECLARE @lineas TABLE (
            IdCarritoDetalle INT NOT NULL
            , IdProductoTalla INT NOT NULL
            , IdProducto INT NOT NULL
            , NombreProducto NVARCHAR(100) NOT NULL
            , RutaImagen VARCHAR(260) NULL
            , Talla NVARCHAR(16) NOT NULL
            , Cantidad INT NOT NULL
            , PrecioUnitario MONEY NOT NULL
            , Subtotal MONEY NOT NULL
            , Existencias INT NOT NULL
            , Disponible BIT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @costoEnvio = NULL;
        SET @envioACoordinar = @false;

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        IF (@inIdMetodoEntrega IS NOT NULL)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.MetodoEntrega AS ME
                WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega)
            )
        BEGIN
            SET @outResultCode = 50020; -- método de entrega no existe
            RETURN;
        END;

        -- preprocesamiento
        SELECT @costoEnvio = ME.CostoEnvio
            , @envioACoordinar = CASE
                WHEN (ME.CostoEnvio IS NULL) THEN @true
                ELSE @false
              END
        FROM dbo.MetodoEntrega AS ME
        WHERE (ME.IdMetodoEntrega = @inIdMetodoEntrega);

        -- se usa el precio vigente (GP020 paso 2.1)
        INSERT INTO @lineas (
            IdCarritoDetalle
            , IdProductoTalla
            , IdProducto
            , NombreProducto
            , RutaImagen
            , Talla
            , Cantidad
            , PrecioUnitario
            , Subtotal
            , Existencias
            , Disponible
        )
        SELECT CD.IdCarritoDetalle
            , CD.IdProductoTalla
            , P.IdProducto
            , P.Nombre
            , P.RutaImagen
            , T.Nombre
            , CD.Cantidad
            , P.Precio
            , P.Precio * CD.Cantidad
            , PT.Cantidad
            , CASE
                WHEN (P.FlagActivo = @true)
                    AND (PT.Cantidad >= CD.Cantidad) THEN @true
                ELSE @false
              END
        FROM dbo.CarritoDetalle AS CD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = CD.IdProductoTalla)
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = PT.IdProducto)
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (CD.IdUsuario = @inIdUsuario);

        -- primer resultado: líneas
        SELECT L.IdCarritoDetalle
            , L.IdProductoTalla
            , L.IdProducto
            , L.NombreProducto
            , L.RutaImagen
            , L.Talla
            , L.Cantidad
            , L.PrecioUnitario
            , L.Subtotal
            , L.Existencias
            , L.Disponible
        FROM @lineas AS L
        ORDER BY L.IdCarritoDetalle;

        -- segundo resultado: resumen. Los no disponibles no suman (GP008 alterno)
        SELECT ISNULL(SUM(CASE WHEN (L.Disponible = @true) THEN L.Subtotal ELSE 0 END), 0) AS SubtotalProductos
            , @costoEnvio AS CostoEnvio
            , @envioACoordinar AS EnvioACoordinar
            , ISNULL(SUM(CASE WHEN (L.Disponible = @true) THEN L.Subtotal ELSE 0 END), 0)
                + ISNULL(@costoEnvio, 0) AS Total
            , COUNT(1) AS CantidadLineas
            , ISNULL(SUM(CASE WHEN (L.Disponible = @false) THEN 1 ELSE 0 END), 0) AS CantidadNoDisponibles
        FROM @lineas AS L;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarCatalogo.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarCatalogo
    @inIdCategoria INT -- categoría (NULL = todas)
    , @inTallasJson NVARCHAR(MAX) -- tallas a filtrar: [2,3] (NULL o vacío = todas)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
CP001 Visualizar catálogo, CP005 disponibilidad, CP006 filtrar por talla,
CP007 filtrar por categoría. Es público (CP009): no recibe usuario.
Los filtros se pueden combinar (CP007 restricción 3).

Devuelve cuatro resultados:
    1. productos (tarjetas), con Disponible = 1 si hay existencias
    2. tallas con existencias de esos productos (CP003)
    3. categorías que tienen productos, para el filtro (CP007 restricción 1)
    4. tallas que tienen existencias, para el filtro (CP006 restricción 1)

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarCatalogo
        @inIdCategoria = NULL
        , @inTallasJson = N'[2,3]'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @tallasJson NVARCHAR(MAX)
            , @hayFiltroTalla BIT;

        -- tallas pedidas en el filtro
        DECLARE @tallasFiltro TABLE (
            IdTalla INT NULL
        );

        -- productos que pasan los filtros
        DECLARE @productos TABLE (
            IdProducto INT NOT NULL PRIMARY KEY
            , Existencias INT NOT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @tallasJson = NULLIF(LTRIM(RTRIM(@inTallasJson)), N'');
        SET @hayFiltroTalla = @false;

        -- validaciones: si viene filtro de tallas debe ser un arreglo válido
        IF (@tallasJson IS NOT NULL)
            AND (
                (ISNULL(ISJSON(@tallasJson), 0) = 0)
                OR (LEFT(@tallasJson, 1) <> '[')
            )
        BEGIN
            SET @outResultCode = 50010; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: separa las tallas del filtro
        INSERT INTO @tallasFiltro (
            IdTalla
        )
        SELECT TRY_CAST(J.value AS INT)
        FROM OPENJSON(ISNULL(@tallasJson, N'[]')) AS J;

        IF EXISTS (
            SELECT 1
            FROM @tallasFiltro AS TF
            WHERE (TF.IdTalla IS NULL)
        )
        BEGIN
            SET @outResultCode = 50010; -- algún valor no era un número
            RETURN;
        END;

        SET @hayFiltroTalla = CASE
                WHEN EXISTS (SELECT 1 FROM @tallasFiltro) THEN @true
                ELSE @false
            END;

        -- productos activos que cumplen los filtros. El de talla solo cuenta
        -- tallas con existencias (CP006 restricción 1)
        INSERT INTO @productos (
            IdProducto
            , Existencias
        )
        SELECT P.IdProducto
            , ISNULL((
                SELECT SUM(PT.Cantidad)
                FROM dbo.ProductoTalla AS PT
                WHERE (PT.IdProducto = P.IdProducto)
              ), 0)
        FROM dbo.Producto AS P
        WHERE (P.FlagActivo = @true)
            AND (
                (@inIdCategoria IS NULL)
                OR (P.IdCategoria = @inIdCategoria)
            )
            AND (
                (@hayFiltroTalla = @false)
                OR EXISTS (
                    SELECT 1
                    FROM dbo.ProductoTalla AS PT
                    INNER JOIN @tallasFiltro AS TF
                        ON (TF.IdTalla = PT.IdTalla)
                    WHERE (PT.IdProducto = P.IdProducto)
                        AND (PT.Cantidad > 0)
                )
            );

        -- primer resultado: tarjetas del catálogo (foto, precio, disponibilidad)
        SELECT P.IdProducto
            , P.Nombre
            , P.Descripcion
            , P.IdCategoria
            , C.Nombre AS Categoria
            , P.Precio
            , P.RutaImagen
            , F.Existencias
            , CASE
                WHEN (F.Existencias > 0) THEN @true
                ELSE @false
              END AS Disponible
        FROM @productos AS F
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = F.IdProducto)
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        ORDER BY Disponible DESC -- los agotados al final
            , P.FechaCreacion DESC;

        -- segundo resultado: tallas con existencias de cada producto (CP003)
        SELECT PT.IdProducto
            , PT.IdProductoTalla
            , PT.IdTalla
            , T.Nombre AS Talla
            , PT.Cantidad
        FROM @productos AS F
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProducto = F.IdProducto)
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (PT.Cantidad > 0)
        ORDER BY PT.IdProducto
            , T.Orden;

        -- tercer resultado: categorías con productos activos
        SELECT C.IdCategoria
            , C.Nombre
        FROM dbo.Categoria AS C
        WHERE EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdCategoria = C.IdCategoria)
                AND (P.FlagActivo = @true)
        )
        ORDER BY C.Nombre;

        -- cuarto resultado: tallas con existencias en algún producto activo
        SELECT T.IdTalla
            , T.Nombre
        FROM dbo.Talla AS T
        WHERE EXISTS (
            SELECT 1
            FROM dbo.ProductoTalla AS PT
            INNER JOIN dbo.Producto AS P
                ON (P.IdProducto = PT.IdProducto)
            WHERE (PT.IdTalla = T.IdTalla)
                AND (PT.Cantidad > 0)
                AND (P.FlagActivo = @true)
        )
        ORDER BY T.Orden;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarDireccion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarDireccion
    @inIdUsuario INT -- cliente dueño de las direcciones
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP003 Visualizar dirección de envío.
Cada cliente solo ve sus propias direcciones activas (restricción 1).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarDireccion
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        SELECT D.IdDireccion
            , D.IdProvincia
            , PR.Nombre AS Provincia
            , D.Canton
            , D.Distrito
            , D.OtrasSenas
        FROM dbo.Direccion AS D
        INNER JOIN dbo.Provincia AS PR
            ON (PR.IdProvincia = D.IdProvincia)
        WHERE (D.IdUsuario = @inIdUsuario)
            AND (D.FlagActivo = @true)
        ORDER BY D.FechaCreacion DESC;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarNotificacionPendiente.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarNotificacionPendiente
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019 Notificar al cliente el estado del pedido.
Lo llama un proceso del backend cada cierto tiempo (por ejemplo cada
minuto con setInterval): toma los correos pendientes, los envía con
Nodemailer y marca cada uno con spMarcarNotificacion.
Los que fallaron se reintentan hasta un máximo de intentos (flujo alternativo).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarNotificacionPendiente
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @false BIT = 0
            , @maxIntentos INT = 5 -- después de 5 fallos se deja de intentar
            , @tamanoLote INT = 20; -- cuántos correos se envían por vuelta

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        SELECT TOP (@tamanoLote)
            N.IdNotificacion
            , N.IdPedido
            , N.Correo
            , N.Asunto
            , N.Mensaje
            , N.Intentos
        FROM dbo.Notificacion AS N
        WHERE (N.FlagEnviado = @false)
            AND (N.Intentos < @maxIntentos)
        ORDER BY N.FechaCreacion
            , N.IdNotificacion; -- los más antiguos primero

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarPedido.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarPedido
    @inIdUsuario INT -- quién consulta
    , @inIdEstadoPedido INT -- filtro por estado (NULL = todos)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP015 (lista de pedidos de la administradora) y GP018 (historial del cliente).
La administradora ve todos los pedidos; un cliente solo ve los suyos
(GP018 restricción 1). Ordenados del más reciente al más antiguo.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarPedido
        @inIdUsuario = 1
        , @inIdEstadoPedido = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = NULL; -- NULL = usuario no existe

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador IS NULL)
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , MP.Nombre AS MetodoPago
            , ME.Nombre AS MetodoEntrega
            , P.Total
            , CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.Comprobante AS CO
                    WHERE (CO.IdPedido = P.IdPedido)
                ) THEN @true
                ELSE @false
              END AS TieneComprobante
        FROM dbo.Pedido AS P
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        INNER JOIN dbo.MetodoPago AS MP
            ON (MP.IdMetodoPago = P.IdMetodoPago)
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (
                (@esAdministrador = @true)
                OR (P.IdUsuario = @inIdUsuario)
            )
            AND (
                (@inIdEstadoPedido IS NULL)
                OR (P.IdEstadoPedido = @inIdEstadoPedido)
            )
        ORDER BY P.FechaCreacion DESC
            , P.IdPedido DESC;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spListarProductoAdmin.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spListarProductoAdmin
    @inIdUsuario INT -- quién consulta, debe ser administradora
    , @inTextoBusqueda NVARCHAR(100) -- palabra clave (NULL o vacío = sin filtro)
    , @inIdCategoria INT -- categoría (NULL = todas)
    , @inIdTalla INT -- talla (NULL = todas)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI004 Consultar productos y GI008 Filtrar/buscar productos.
Con todos los filtros en NULL devuelve el inventario completo (GI008
criterio 2: al quitar el filtro vuelve a verse todo).

Devuelve dos resultados:
    1. productos (una fila por producto)
    2. tallas de esos productos con su cantidad (se unen en Node por IdProducto)

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarProductoAdmin
        @inIdUsuario = 1
        , @inTextoBusqueda = N'blusa'
        , @inIdCategoria = NULL
        , @inIdTalla = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @texto NVARCHAR(100);

        -- productos que pasan los filtros
        DECLARE @productos TABLE (
            IdProducto INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @texto = NULLIF(LTRIM(RTRIM(@inTextoBusqueda)), N'');

        -- validaciones: GI004 restricción 1, solo administración
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- preprocesamiento: se aplica cada filtro solo si viene con valor
        INSERT INTO @productos (
            IdProducto
        )
        SELECT P.IdProducto
        FROM dbo.Producto AS P
        WHERE (P.FlagActivo = @true)
            AND (
                (@texto IS NULL)
                OR (P.Nombre LIKE N'%' + @texto + N'%')
                OR (P.Descripcion LIKE N'%' + @texto + N'%')
            )
            AND (
                (@inIdCategoria IS NULL)
                OR (P.IdCategoria = @inIdCategoria)
            )
            AND (
                (@inIdTalla IS NULL)
                OR EXISTS (
                    SELECT 1
                    FROM dbo.ProductoTalla AS PT
                    WHERE (PT.IdProducto = P.IdProducto)
                        AND (PT.IdTalla = @inIdTalla)
                )
            );

        -- primer resultado: productos con el total de existencias
        SELECT P.IdProducto
            , P.Nombre
            , P.Descripcion
            , P.IdCategoria
            , C.Nombre AS Categoria
            , P.Precio
            , P.RutaImagen
            , ISNULL((
                SELECT SUM(PT.Cantidad)
                FROM dbo.ProductoTalla AS PT
                WHERE (PT.IdProducto = P.IdProducto)
              ), 0) AS Existencias
            , P.FechaCreacion
        FROM @productos AS F
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = F.IdProducto)
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        ORDER BY P.FechaCreacion DESC; -- lo más reciente primero

        -- segundo resultado: tallas registradas de esos productos
        SELECT PT.IdProducto
            , PT.IdTalla
            , T.Nombre AS Talla
            , PT.Cantidad
        FROM @productos AS F
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProducto = F.IdProducto)
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        ORDER BY PT.IdProducto
            , T.Orden;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spMarcarNotificacion.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spMarcarNotificacion
    @inIdNotificacion INT -- notificación que se procesó
    , @inFlagEnviado BIT -- 1 = el correo salió bien, 0 = falló
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP019: registra el resultado del envío de un correo.
Si salió bien queda marcado con su fecha; si falló se suma un intento para
reintentarlo en la siguiente vuelta (flujo alternativo). En ambos casos el
nuevo estado ya es visible para el cliente en su historial.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spMarcarNotificacion
        @inIdNotificacion = 1
        , @inFlagEnviado = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Notificacion AS N
            WHERE (N.IdNotificacion = @inIdNotificacion)
                AND (N.FlagEnviado = @false)
        )
        BEGIN
            SET @outResultCode = 50027; -- no existe o ya estaba enviada
            RETURN;
        END;

        BEGIN TRANSACTION tMarcarNotificacion;

            UPDATE dbo.Notificacion
            SET FlagEnviado = ISNULL(@inFlagEnviado, @false)
                , FechaEnvio = CASE
                    WHEN (@inFlagEnviado = @true) THEN GETDATE()
                    ELSE NULL
                  END
                , Intentos = Intentos + 1
            WHERE (IdNotificacion = @inIdNotificacion);

        COMMIT TRANSACTION tMarcarNotificacion;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spObtenerCatalogos.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spObtenerCatalogos
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Devuelve todos los catálogos que el sitio necesita para llenar listas
desplegables (formularios de producto, dirección, pago y entrega).

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCatalogos
        @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- primer resultado: categorías
        SELECT C.IdCategoria
            , C.Nombre
        FROM dbo.Categoria AS C
        ORDER BY C.Nombre;

        -- segundo resultado: tallas, en su orden lógico (XS, S, M...)
        SELECT T.IdTalla
            , T.Nombre
        FROM dbo.Talla AS T
        ORDER BY T.Orden;

        -- tercer resultado: provincias
        SELECT PR.IdProvincia
            , PR.Nombre
        FROM dbo.Provincia AS PR
        ORDER BY PR.IdProvincia;

        -- cuarto resultado: métodos de pago
        SELECT MP.IdMetodoPago
            , MP.Nombre
            , MP.FlagRequiereComprobante
            , MP.FlagSoloRetiro
        FROM dbo.MetodoPago AS MP
        ORDER BY MP.IdMetodoPago;

        -- quinto resultado: métodos de entrega
        SELECT ME.IdMetodoEntrega
            , ME.Nombre
            , ME.FlagRequiereDireccion
            , ME.CostoEnvio
        FROM dbo.MetodoEntrega AS ME
        ORDER BY ME.IdMetodoEntrega;

        -- sexto resultado: estados de pedido
        SELECT EP.IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo
        FROM dbo.EstadoPedido AS EP
        ORDER BY EP.IdEstadoPedido;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spObtenerPedido.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spObtenerPedido
    @inIdUsuario INT -- quién consulta
    , @inIdPedido INT -- pedido que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP015 Visualizar comprobantes por administrador (detalle) y detalle de
GP018 Consultar historial de pedido. Solo la administradora o el dueño.

Devuelve cuatro resultados:
    1. encabezado del pedido, con la ruta del comprobante (NULL si es efectivo)
    2. productos
    3. historial de estados
    4. estados a los que puede pasar (solo para la administradora; vacío
       para el cliente). Sirve para GP017 paso 2.1

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerPedido
        @inIdUsuario = 1
        , @inIdPedido = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idDueno INT
            , @idEstadoActual INT
            , @requiereDireccion BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idDueno = NULL;

        -- validaciones
        SELECT @idDueno = P.IdUsuario
            , @idEstadoActual = P.IdEstadoPedido
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        -- mismo código si no existe o si es de otro cliente: no se revela
        -- que existe un pedido ajeno
        IF (@idDueno IS NULL)
            OR (
                (@esAdministrador = @false)
                AND (@idDueno <> @inIdUsuario)
            )
        BEGIN
            SET @outResultCode = 50024; -- pedido no existe o sin acceso
            RETURN;
        END;

        -- primer resultado: encabezado
        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , U.Correo
            , U.Telefono
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , P.MotivoEstado
            , MP.Nombre AS MetodoPago
            , MP.FlagRequiereComprobante
            , ME.Nombre AS MetodoEntrega
            , ME.FlagRequiereDireccion
            , P.DireccionEntrega
            , P.SubtotalProductos
            , P.CostoEnvio
            , P.Total
            , CO.RutaArchivo AS RutaComprobante -- NULL = efectivo (GP015 alterno)
            , CO.FechaSubida AS FechaComprobante
        FROM dbo.Pedido AS P
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        INNER JOIN dbo.MetodoPago AS MP
            ON (MP.IdMetodoPago = P.IdMetodoPago)
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        LEFT JOIN dbo.Comprobante AS CO
            ON (CO.IdPedido = P.IdPedido)
        WHERE (P.IdPedido = @inIdPedido);

        -- segundo resultado: productos (copia del momento de la compra)
        SELECT PD.IdPedidoDetalle
            , PD.NombreProducto
            , PD.NombreTalla
            , PD.PrecioUnitario
            , PD.Cantidad
            , PD.Subtotal
            , PR.RutaImagen
        FROM dbo.PedidoDetalle AS PD
        INNER JOIN dbo.ProductoTalla AS PT
            ON (PT.IdProductoTalla = PD.IdProductoTalla)
        INNER JOIN dbo.Producto AS PR
            ON (PR.IdProducto = PT.IdProducto)
        WHERE (PD.IdPedido = @inIdPedido)
        ORDER BY PD.IdPedidoDetalle;

        -- tercer resultado: historial de estados
        SELECT HEP.FechaHora
            , EP.Nombre AS Estado
            , HEP.Comentario
        FROM dbo.HistorialEstadoPedido AS HEP
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = HEP.IdEstadoPedido)
        WHERE (HEP.IdPedido = @inIdPedido)
        ORDER BY HEP.FechaHora
            , HEP.IdHistorialEstadoPedido;

        -- cuarto resultado: siguientes estados permitidos, según el estado
        -- actual y si el pedido es con envío o con retiro
        SELECT EP.IdEstadoPedido
            , EP.Nombre
            , EP.FlagRequiereMotivo
        FROM dbo.TransicionEstadoPedido AS TEP
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = TEP.IdEstadoNuevo)
        WHERE (@esAdministrador = @true)
            AND (TEP.IdEstadoActual = @idEstadoActual)
            AND (
                (TEP.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TEP.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            )
        ORDER BY EP.IdEstadoPedido;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spObtenerProducto.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spObtenerProducto
    @inIdProducto INT -- producto que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
CP008 Ver detalles del producto (público) y carga del formulario de
GI005 Modificar producto (la administradora ve también las tallas en 0).

Devuelve dos resultados:
    1. el producto
    2. todas sus tallas registradas con cantidad y Disponible

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerProducto
        @inIdProducto = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- CP008 flujo alternativo: el producto fue eliminado mientras se veía
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Producto AS P
            WHERE (P.IdProducto = @inIdProducto)
                AND (P.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50011; -- producto no existe o fue eliminado
            RETURN;
        END;

        -- primer resultado: el producto
        SELECT P.IdProducto
            , P.Nombre
            , P.Descripcion
            , P.IdCategoria
            , C.Nombre AS Categoria
            , P.Precio
            , P.RutaImagen
            , CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.ProductoTalla AS PT
                    WHERE (PT.IdProducto = P.IdProducto)
                        AND (PT.Cantidad > 0)
                ) THEN @true
                ELSE @false
              END AS Disponible
        FROM dbo.Producto AS P
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        WHERE (P.IdProducto = @inIdProducto);

        -- segundo resultado: tallas. El catálogo muestra solo Disponible = 1
        SELECT PT.IdProductoTalla
            , PT.IdTalla
            , T.Nombre AS Talla
            , PT.Cantidad
            , CASE
                WHEN (PT.Cantidad > 0) THEN @true
                ELSE @false
              END AS Disponible
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (PT.IdProducto = @inIdProducto)
        ORDER BY T.Orden;

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spObtenerUsuarioLogin.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spObtenerUsuarioLogin
    @inCorreo VARCHAR(128) -- correo con el que intenta ingresar
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI001 y GP002 Iniciar sesión.
Con bcrypt la comparación del password no se puede hacer en SQL: este SP
devuelve el hash y Node lo compara con bcrypt.compare(). Si no coincide,
Node responde el mismo mensaje que cuando el correo no existe (GP002: no se
dice cuál dato falló). El hash nunca se manda al navegador.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerUsuarioLogin
        @inCorreo = 'admin@capanni.com'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1;

        -- variables de uso general
        DECLARE @idUsuario INT; -- queda en NULL si no hay coincidencia

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @idUsuario = NULL;

        -- validaciones
        SELECT @idUsuario = U.IdUsuario
        FROM dbo.Usuario AS U
        WHERE (U.Correo = LOWER(LTRIM(RTRIM(@inCorreo))))
            AND (U.FlagActivo = @true);

        IF (@idUsuario IS NULL)
        BEGIN
            SET @outResultCode = 50001; -- credenciales incorrectas
            RETURN;
        END;

        -- datos del usuario con el hash, solo para que Node lo compare
        SELECT U.IdUsuario
            , U.Nombre
            , U.Correo
            , U.PassHash
            , U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @idUsuario);

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spRegistrarCliente.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spRegistrarCliente
    @inNombre NVARCHAR(100) -- nombre completo
    , @inCorreo VARCHAR(128) -- correo, se usa para iniciar sesión
    , @inTelefono VARCHAR(16) -- teléfono de 8 dígitos
    , @inPassHash VARCHAR(100) -- hash bcrypt generado en Node (nunca el password)
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP001 Registrar cliente.
El largo mínimo de 8 caracteres del password se valida en Node antes de
generar el hash: aquí ya solo llega el hash.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spRegistrarCliente
        @inNombre = N'Ana Mora Solís'
        , @inCorreo = 'ana@gmail.com'
        , @inTelefono = '88112233'
        , @inPassHash = '$2b$10$hashDePrueba'
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @tipoOperacionRegistrar INT = 1 -- TipoOperacion "Registrar cliente"
            , @largoTelefono INT = 8;

        -- variables de uso general
        DECLARE @nombre NVARCHAR(100)
            , @correo VARCHAR(128)
            , @telefono VARCHAR(16)
            , @passHash VARCHAR(100);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- se limpian espacios; el correo se guarda en minúscula para que
        -- "Ana@Gmail.com" y "ana@gmail.com" cuenten como el mismo
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @correo = LOWER(LTRIM(RTRIM(ISNULL(@inCorreo, ''))));
        SET @telefono = LTRIM(RTRIM(ISNULL(@inTelefono, '')));
        SET @passHash = ISNULL(@inPassHash, '');

        -- validaciones
        -- campos obligatorios
        IF (@nombre = '')
            OR (@passHash = '')
        BEGIN
            SET @outResultCode = 50003; -- campo obligatorio vacío
            RETURN;
        END;

        -- correo con formato básico algo@algo.algo y sin espacios
        IF (@correo NOT LIKE '%_@_%._%')
            OR (@correo LIKE '% %')
        BEGIN
            SET @outResultCode = 50004; -- correo inválido
            RETURN;
        END;

        -- teléfono de 8 dígitos
        IF (LEN(@telefono) <> @largoTelefono)
            OR (@telefono LIKE '%[^0-9]%')
        BEGIN
            SET @outResultCode = 50006; -- teléfono inválido
            RETURN;
        END;

        -- correo único (GP001 restricción 2)
        IF EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.Correo = @correo)
        )
        BEGIN
            SET @outResultCode = 50005; -- correo ya registrado
            RETURN;
        END;

        -- variables para la transacción
        DECLARE @idUsuario INT
            , @jsonDespues NVARCHAR(MAX);

        -- transacción: el usuario y su registro en bitácora van juntos
        BEGIN TRANSACTION tRegistrarCliente;

            INSERT INTO dbo.Usuario (
                Nombre
                , Correo
                , Telefono
                , PassHash
            )
            VALUES (
                @nombre
                , @correo
                , @telefono
                , @passHash
            );

            SET @idUsuario = SCOPE_IDENTITY();

            -- JSON sin el hash: la bitácora nunca guarda credenciales
            SET @jsonDespues = (
                SELECT @idUsuario AS IdUsuario
                    , @nombre AS Nombre
                    , @correo AS Correo
                    , @telefono AS Telefono
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @idUsuario
                , @tipoOperacionRegistrar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tRegistrarCliente;

        -- resultado para la capa lógica
        SELECT @idUsuario AS IdUsuario;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        -- 2627/2601 = violó el UNIQUE del correo (dos registros simultáneos)
        SET @outResultCode = CASE
                WHEN (ERROR_NUMBER() IN (2627, 2601)) THEN 50005
                ELSE 50000 -- error inesperado
            END;

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

-------------------------------------------------------------------------------
-- sp/spVaciarCarrito.sql
-------------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spVaciarCarrito
    @inIdUsuario INT -- cliente dueño del carrito
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP010 Eliminar carrito.
No afecta el inventario (restricción 2). La confirmación la hace el frontend.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spVaciarCarrito
        @inIdUsuario = 2
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones: GP010 precondición 2, debe tener al menos un producto
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.CarritoDetalle AS CD
            WHERE (CD.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50017; -- el carrito está vacío
            RETURN;
        END;

        BEGIN TRANSACTION tVaciarCarrito;

            DELETE FROM dbo.CarritoDetalle
            WHERE (IdUsuario = @inIdUsuario);

        COMMIT TRANSACTION tVaciarCarrito;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO

