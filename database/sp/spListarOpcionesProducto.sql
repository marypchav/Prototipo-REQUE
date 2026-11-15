CREATE OR ALTER PROCEDURE dbo.spListarOpcionesProducto
    @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Opciones para el formulario de agregar/modificar producto (GI002, GI005):
todas las categorías y todas las tallas registradas, tengan o no productos.
(El catálogo solo muestra las que tienen productos; aquí se necesitan todas.)

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarOpcionesProducto
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

        -- segundo resultado: tallas, en su orden (XS, S, M...)
        SELECT T.IdTalla
            , T.Nombre
        FROM dbo.Talla AS T
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
