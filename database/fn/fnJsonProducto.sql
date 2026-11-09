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
