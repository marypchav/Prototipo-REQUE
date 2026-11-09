CREATE OR ALTER PROCEDURE dbo.spListarProductoAdmin
    @inIdUsuario INT -- quién consulta, debe ser administradora
    , @inTextoBusqueda NVARCHAR(100) -- palabra clave (NULL o vacío = sin filtro)
    , @inIdCategoria INT -- categoría (NULL = todas)
    , @inIdTalla INT -- talla (NULL = todas)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI004 Consultar productos y GI008 Filtrar/buscar productos.
Con todos los filtros en NULL devuelve el inventario completo (GI008
criterio 2: al quitar el filtro vuelve a verse todo).

Devuelve dos resultados:
    1. productos (una fila por producto)
    2. tallas de esos productos con su cantidad (se unen en Node por IdProducto)

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarProductoAdmin
        @inIdUsuario = 1
        , @inTextoBusqueda = N'blusa'
        , @inIdCategoria = NULL
        , @inIdTalla = NULL
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
        DECLARE @esAdministrador BIT
            , @texto NVARCHAR(100);

        -- productos que pasan los filtros
        DECLARE @productos TABLE (
            IdProducto INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @texto = NULLIF(LTRIM(RTRIM(@inTextoBusqueda)), N'');

        -- validaciones: GI004 restricción 1, solo administración
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        -- preprocesamiento: se aplica cada filtro solo si viene con valor
        INSERT INTO @productos (
            IdProducto
        )
        SELECT P.IdProducto
        FROM dbo.Producto AS P
        WHERE (P.FlagActivo = @true)
            AND (
                (@texto IS NULL)
                OR (P.Nombre LIKE N'%' + @texto + N'%')
                OR (P.Descripcion LIKE N'%' + @texto + N'%')
            )
            AND (
                (@inIdCategoria IS NULL)
                OR (P.IdCategoria = @inIdCategoria)
            )
            AND (
                (@inIdTalla IS NULL)
                OR EXISTS (
                    SELECT 1
                    FROM dbo.ProductoTalla AS PT
                    WHERE (PT.IdProducto = P.IdProducto)
                        AND (PT.IdTalla = @inIdTalla)
                )
            );

        -- primer resultado: productos con el total de existencias
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
              ), 0) AS Existencias
            , P.FechaCreacion
        FROM @productos AS F
        INNER JOIN dbo.Producto AS P
            ON (P.IdProducto = F.IdProducto)
        INNER JOIN dbo.Categoria AS C
            ON (C.IdCategoria = P.IdCategoria)
        ORDER BY P.FechaCreacion DESC; -- lo más reciente primero

        -- segundo resultado: tallas registradas de esos productos
        SELECT PT.IdProducto
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
