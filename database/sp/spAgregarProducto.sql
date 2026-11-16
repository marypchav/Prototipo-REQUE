CREATE OR ALTER PROCEDURE dbo.spAgregarProducto
    @inNombre NVARCHAR(100) -- nombre del producto
    , @inDescripcion NVARCHAR(500) -- descripción (opcional)
    , @inIdCategoria INT -- categoría del producto
    , @inPrecio DECIMAL(12, 2) -- precio en colones
    , @inTallasJson NVARCHAR(MAX) -- existencias por talla: [{"idTalla":2,"cantidad":5}]
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GI002 Agregar producto. Solo lo usa la administradora: el backend revisa la
sesión antes de llamarlo. El producto queda sin foto; la foto se asigna
después con spActualizarImagenProducto (GI003, postcondición de GI002).
Las existencias se guardan por talla en ProductoTalla.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarProducto
        @inNombre = N'Blusa de lino'
        , @inDescripcion = N'Blusa manga corta, lino 100 %'
        , @inIdCategoria = 1
        , @inPrecio = 12500
        , @inTallasJson = N'[{"idTalla":2,"cantidad":3},{"idTalla":3,"cantidad":1}]'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @sinExistencias INT = 0;

        -- variables de uso general
        DECLARE @nombre NVARCHAR(100)
            , @descripcion NVARCHAR(500)
            , @tallasJson NVARCHAR(MAX)
            , @idProducto INT;

        -- existencias por talla que llegan en el JSON
        DECLARE @tallas TABLE (
            IdTalla INT NULL
            , CantidadTexto NVARCHAR(50) NULL
            , Cantidad INT NULL
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @nombre = NULLIF(LTRIM(RTRIM(@inNombre)), N'');
        SET @descripcion = ISNULL(LTRIM(RTRIM(@inDescripcion)), N'');
        SET @tallasJson = NULLIF(LTRIM(RTRIM(@inTallasJson)), N'');

        -- validaciones (GI002 restricciones 1 y 2)
        IF (@nombre IS NULL)
            OR (@inIdCategoria IS NULL)
        BEGIN
            SET @outResultCode = 50021; -- campos obligatorios vacíos
            RETURN;
        END;

        IF (@inPrecio IS NULL)
            OR (@inPrecio <= 0)
        BEGIN
            SET @outResultCode = 50022; -- precio inválido
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Categoria AS C
            WHERE (C.IdCategoria = @inIdCategoria)
        )
        BEGIN
            SET @outResultCode = 50023; -- la categoría no existe
            RETURN;
        END;

        IF (@tallasJson IS NULL)
            OR (ISNULL(ISJSON(@tallasJson), 0) = 0)
            OR (LEFT(@tallasJson, 1) <> '[')
        BEGIN
            SET @outResultCode = 50025; -- lista de tallas inválida
            RETURN;
        END;

        -- preprocesamiento: separa las tallas del JSON. La cantidad se lee como
        -- texto para poder rechazar negativos, decimales y letras
        INSERT INTO @tallas (
            IdTalla
            , CantidadTexto
        )
        SELECT TRY_CAST(J.IdTalla AS INT)
            , LTRIM(RTRIM(J.Cantidad))
        FROM OPENJSON(@tallasJson)
        WITH (
            IdTalla NVARCHAR(50) '$.idTalla'
            , Cantidad NVARCHAR(50) '$.cantidad'
        ) AS J;

        UPDATE @tallas
        SET Cantidad = CASE
                WHEN (CantidadTexto NOT LIKE N'%[^0-9]%')
                    AND (LEN(CantidadTexto) BETWEEN 1 AND 9)
                    THEN TRY_CAST(CantidadTexto AS INT)
                ELSE NULL
            END;

        -- talla vacía, inexistente o repetida
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.IdTalla IS NULL)
                OR NOT EXISTS (
                    SELECT 1
                    FROM dbo.Talla AS T
                    WHERE (T.IdTalla = TA.IdTalla)
                )
        )
            OR EXISTS (
                SELECT TA.IdTalla
                FROM @tallas AS TA
                GROUP BY TA.IdTalla
                HAVING (COUNT(*) > 1)
            )
        BEGIN
            SET @outResultCode = 50025; -- lista de tallas inválida
            RETURN;
        END;

        -- GI002 flujo alternativo: negativos, letras o decimales en la cantidad
        IF EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad IS NULL)
        )
        BEGIN
            SET @outResultCode = 50024; -- cantidad inválida
            RETURN;
        END;

        -- GI002 restricción 1: la cantidad debe ser positiva
        IF NOT EXISTS (
            SELECT 1
            FROM @tallas AS TA
            WHERE (TA.Cantidad > @sinExistencias)
        )
        BEGIN
            SET @outResultCode = 50026; -- ninguna talla con existencias
            RETURN;
        END;

        -- el producto y sus tallas se guardan juntos o no se guarda nada
        BEGIN TRANSACTION tAgregarProducto;

            INSERT INTO dbo.Producto (
                Nombre
                , Descripcion
                , IdCategoria
                , Precio
                , RutaImagen
                , FlagActivo
                , FechaCreacion
            )
            VALUES (
                @nombre
                , @descripcion
                , @inIdCategoria
                , @inPrecio
                , NULL -- la foto se sube después (GI003)
                , @true
                , GETDATE()
            );

            SET @idProducto = SCOPE_IDENTITY();

            -- las tallas en 0 no se guardan
            INSERT INTO dbo.ProductoTalla (
                IdProducto
                , IdTalla
                , Cantidad
            )
            SELECT @idProducto
                , TA.IdTalla
                , TA.Cantidad
            FROM @tallas AS TA
            WHERE (TA.Cantidad > @sinExistencias);

        COMMIT TRANSACTION tAgregarProducto;

        -- primer resultado: el producto creado, para subirle la foto
        SELECT @idProducto AS IdProducto;

    END TRY
    BEGIN CATCH

        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION; -- deshace el producto a medio guardar
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
