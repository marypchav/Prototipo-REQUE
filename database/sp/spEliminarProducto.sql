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
