CREATE OR ALTER PROCEDURE dbo.spObtenerProducto
    @inIdProducto INT -- producto que se consulta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
CP008 Ver detalles del producto. También lo usa CP011: el enlace compartido
abre este mismo detalle. Es público (CP009): no recibe usuario.

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
            , @false BIT = 0
            , @sinExistencias INT = 0;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- CP008 y CP011 flujo alternativo: el producto no existe o fue eliminado
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
                        AND (PT.Cantidad > @sinExistencias)
                ) THEN @true
                ELSE @false
              END AS Disponible
        FROM dbo.Producto AS P
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        WHERE (P.IdProducto = @inIdProducto);

        -- segundo resultado: tallas con existencias, en su orden (XS, S, M...)
        SELECT PT.IdProductoTalla
            , PT.IdTalla
            , T.Nombre AS Talla
            , PT.Cantidad
        FROM dbo.ProductoTalla AS PT
        INNER JOIN dbo.Talla AS T
            ON (T.IdTalla = PT.IdTalla)
        WHERE (PT.IdProducto = @inIdProducto)
            AND (PT.Cantidad > @sinExistencias)
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
