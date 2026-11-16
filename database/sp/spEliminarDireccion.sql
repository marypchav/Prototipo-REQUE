CREATE OR ALTER PROCEDURE dbo.spEliminarDireccion
    @inIdUsuario INT -- cliente con sesión iniciada
    , @inIdDireccion INT -- dirección que se elimina
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP006 Eliminar dirección de envío. La confirmación "¿Confirma que desea
eliminar esta dirección?" (restricción 1) la pide el frontend.
Borrado lógico (FlagActivo = 0): deja de mostrarse y de ofrecerse en GP012
(criterio 2). Los pedidos no se afectan porque guardan la dirección en texto.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarDireccion
        @inIdUsuario = 2
        , @inIdDireccion = 1
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

        -- validaciones: debe existir y ser del cliente (GP006 precondición 2)
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Direccion AS D
            WHERE (D.IdDireccion = @inIdDireccion)
                AND (D.IdUsuario = @inIdUsuario)
                AND (D.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50044; -- la dirección no existe
            RETURN;
        END;

        UPDATE dbo.Direccion
        SET FlagActivo = @false
        WHERE (IdDireccion = @inIdDireccion)
            AND (IdUsuario = @inIdUsuario);

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace lo que quedó a medias
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
