CREATE OR ALTER PROCEDURE dbo.spListarCatalogo
    @inIdCategoria INT -- categoría (NULL = todas)
    , @inTallasJson NVARCHAR(MAX) -- tallas a filtrar: [2,3] (NULL o vacío = todas)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
CP001 Visualizar catálogo, CP005 disponibilidad, CP006 filtrar por talla,
CP007 filtrar por categoría. Es público (CP009): no recibe usuario.
Los filtros se pueden combinar (CP007 restricción 3).

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
            , P.FechaCreacion DESC -- lo más reciente primero
            , P.IdProducto DESC; -- desempate: orden estable entre cargas iguales

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
