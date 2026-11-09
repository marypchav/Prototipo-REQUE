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
