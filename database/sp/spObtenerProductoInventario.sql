CREATE OR ALTER PROCEDURE dbo.spObtenerProductoInventario
    @inIdProducto INT -- producto que se va a modificar
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI005 paso 2.1: carga los datos actuales del producto para llenar el
formulario de modificar, así la administradora no digita todo de nuevo.
Devuelve TODAS las tallas del sistema con la cantidad del producto
(0 si no la tiene), para que el formulario muestre una casilla por talla.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerProductoInventario
        @inIdProducto = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @sinExistencias INT = 0;

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
            , ISNULL((
                SELECT SUM(PT.Cantidad)
                FROM dbo.ProductoTalla AS PT
                WHERE (PT.IdProducto = P.IdProducto)
              ), @sinExistencias) AS Existencias
        FROM dbo.Producto AS P
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        WHERE (P.IdProducto = @inIdProducto);

        -- segundo resultado: todas las tallas con la cantidad de este producto
        SELECT T.IdTalla
            , T.Nombre AS Talla
            , PT.IdProductoTalla -- NULL si el producto nunca tuvo esa talla
            , ISNULL(PT.Cantidad, @sinExistencias) AS Cantidad
        FROM dbo.Talla AS T
        LEFT JOIN dbo.ProductoTalla AS PT
            ON (PT.IdTalla = T.IdTalla)
            AND (PT.IdProducto = @inIdProducto)
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
