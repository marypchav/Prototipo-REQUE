CREATE OR ALTER PROCEDURE dbo.spEliminarProducto
    @inIdProducto INT -- producto que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI006 Eliminar producto. La confirmación "¿Confirma que desea eliminar...?"
(restricción 1) la pide el frontend antes de llamar a la API.

El borrado es lógico (FlagActivo = 0): el producto deja de verse en el
inventario y en el catálogo (criterio de aceptación 2), pero la fila se
conserva porque el historial de ventas debe ser inmutable y conservar los
detalles de cada venta (ERS 2.4 y GI009 restricción 2). Un DELETE físico
rompería los pedidos que ya lo referencian.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarProducto
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

        -- un solo UPDATE: es atómico, no necesita transacción explícita.
        -- FechaDesactivacion deja registrado cuándo se eliminó
        UPDATE dbo.Producto
        SET FlagActivo = @false
            , FechaDesactivacion = GETDATE()
        WHERE (IdProducto = @inIdProducto)
            AND (FlagActivo = @true);

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
