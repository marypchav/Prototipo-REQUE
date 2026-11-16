CREATE OR ALTER PROCEDURE dbo.spListarInventario
    @inBusqueda NVARCHAR(100) -- palabra clave (NULL o vacío = sin búsqueda)
    , @inIdCategoria INT -- categoría (NULL = todas)
    , @inTallasJson NVARCHAR(MAX) -- tallas a filtrar: [2,3] (NULL o vacío = todas)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI004 Consultar productos y GI008 Filtrar/buscar productos. Solo para la
administradora (el backend revisa la sesión). A diferencia del catálogo,
muestra también los agotados y las tallas en 0, con cantidades exactas.
La búsqueda compara la palabra clave con nombre, descripción y categoría.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarInventario
        @inBusqueda = N'blusa'
        , @inIdCategoria = NULL
        , @inTallasJson = N'[2,3]'
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

        -- variables de uso general
        DECLARE @busqueda NVARCHAR(100)
            , @patron NVARCHAR(310)
            , @tallasJson NVARCHAR(MAX)
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
        SET @busqueda = NULLIF(LTRIM(RTRIM(@inBusqueda)), N'');
        SET @tallasJson = NULLIF(LTRIM(RTRIM(@inTallasJson)), N'');
        SET @hayFiltroTalla = @false;

        -- los caracteres especiales de LIKE (%, _ y [) se buscan como texto normal
        SET @patron = N'%'
            + REPLACE(REPLACE(REPLACE(@busqueda, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]')
            + N'%';

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

        -- productos activos que cumplen los filtros (GI008).
        -- El filtro de talla busca productos que tengan existencias en esa talla
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
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        WHERE (P.FlagActivo = @true)
            AND (
                (@busqueda IS NULL)
                OR (P.Nombre LIKE @patron)
                OR (P.Descripcion LIKE @patron)
                OR (C.Nombre LIKE @patron)
            )
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
                        AND (PT.Cantidad > @sinExistencias)
                )
            );

        -- primer resultado: productos del inventario
        SELECT P.IdProducto
            , P.Nombre
            , P.Descripcion
            , P.IdCategoria
            , C.Nombre AS Categoria
            , P.Precio
            , P.RutaImagen
            , F.Existencias
            , CASE
                WHEN (F.Existencias > @sinExistencias) THEN @true
                ELSE @false
              END AS Disponible
            , P.FechaCreacion
        FROM @productos AS F
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = F.IdProducto)
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        ORDER BY P.FechaCreacion DESC -- lo más reciente primero
            , P.IdProducto DESC; -- desempate: orden estable

        -- segundo resultado: todas las tallas registradas de cada producto, incluso en 0
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
        ORDER BY PT.IdProducto
            , T.Orden;

        -- tercer resultado: todas las categorías, para el menú de filtros (GI008 restricción 1)
        SELECT C.IdCategoria
            , C.Nombre
        FROM dbo.Categoria AS C
        ORDER BY C.Nombre;

        -- cuarto resultado: todas las tallas, para el menú de filtros
        SELECT T.IdTalla
            , T.Nombre
        FROM dbo.Talla AS T
        ORDER BY T.Orden;

        -- quinto resultado: total de productos activos. Sirve para distinguir
        -- "aún no hay productos" (GI004) de "no hay coincidencias" (GI008)
        SELECT COUNT(*) AS TotalInventario
        FROM dbo.Producto AS P
        WHERE (P.FlagActivo = @true);

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
