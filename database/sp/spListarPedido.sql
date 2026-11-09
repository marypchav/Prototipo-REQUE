CREATE OR ALTER PROCEDURE dbo.spListarPedido
    @inIdUsuario INT -- quién consulta
    , @inIdEstadoPedido INT -- filtro por estado (NULL = todos)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP015 (lista de pedidos de la administradora) y GP018 (historial del cliente).
La administradora ve todos los pedidos; un cliente solo ve los suyos
(GP018 restricción 1). Ordenados del más reciente al más antiguo.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarPedido
        @inIdUsuario = 1
        , @inIdEstadoPedido = NULL
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
        DECLARE @esAdministrador BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = NULL; -- NULL = usuario no existe

        -- validaciones
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador IS NULL)
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        SELECT P.IdPedido
            , P.FechaCreacion
            , U.Nombre AS Cliente
            , P.IdEstadoPedido
            , EP.Nombre AS Estado
            , MP.Nombre AS MetodoPago
            , ME.Nombre AS MetodoEntrega
            , P.Total
            , CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM dbo.Comprobante AS CO
                    WHERE (CO.IdPedido = P.IdPedido)
                ) THEN @true
                ELSE @false
              END AS TieneComprobante
        FROM dbo.Pedido AS P
        INNER JOIN dbo.Usuario AS U
            ON (U.IdUsuario = P.IdUsuario)
        INNER JOIN dbo.EstadoPedido AS EP
            ON (EP.IdEstadoPedido = P.IdEstadoPedido)
        INNER JOIN dbo.MetodoPago AS MP
            ON (MP.IdMetodoPago = P.IdMetodoPago)
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (
                (@esAdministrador = @true)
                OR (P.IdUsuario = @inIdUsuario)
            )
            AND (
                (@inIdEstadoPedido IS NULL)
                OR (P.IdEstadoPedido = @inIdEstadoPedido)
            )
        ORDER BY P.FechaCreacion DESC
            , P.IdPedido DESC;

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
