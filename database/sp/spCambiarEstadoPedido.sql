CREATE OR ALTER PROCEDURE dbo.spCambiarEstadoPedido
    @inIdUsuario INT -- administradora con sesión iniciada
    , @inIdPedido INT -- pedido que cambia de estado
    , @inIdEstadoNuevo INT -- estado al que pasa
    , @inMotivo NVARCHAR(300) -- obligatorio si el estado lo pide (Rechazado)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP016 Confirmar pedido por administrador (Confirmado o Rechazado) y
GP017 Actualizar estado de pedido. Un solo SP porque las reglas salen de
las tablas, sin números fijos:
  - TransicionEstadoPedido: solo transiciones válidas, siempre hacia adelante
    (GP016 restricción 2, GP017 restricción 2). FlagSoloEnvio / FlagSoloRetiro
    según el método de entrega ("Enviado" o "Listo para retiro").
  - EstadoPedido.FlagRequiereMotivo: motivo obligatorio (GP016 restricción 3).
  - EstadoPedido.FlagDevuelveInventario: devuelve los productos al inventario
    (GP016 flujo alterno 1, GP017 restricción 3).
Registra fecha y hora en el historial y deja la notificación lista para que
el backend envíe el correo (GP019). Todo en una transacción con el pedido
bloqueado, así dos clics seguidos no cambian el estado dos veces.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCambiarEstadoPedido
        @inIdUsuario = 1
        , @inIdPedido = 1
        , @inIdEstadoNuevo = 8
        , @inMotivo = N'El comprobante no corresponde al monto del pedido'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @sinIntentos INT = 0;

        -- variables de uso general
        DECLARE @motivo NVARCHAR(300)
            , @nombreEstado NVARCHAR(32)
            , @requiereMotivo BIT
            , @devuelveInventario BIT
            , @estadoActual INT
            , @requiereDireccion BIT
            , @idCliente INT
            , @idNotificacion INT
            , @numeroPedido NVARCHAR(12);

        -- productos que vuelven al inventario, para avisar al catálogo (CP010)
        DECLARE @productosDevueltos TABLE (
            IdProducto INT NOT NULL PRIMARY KEY
        );

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @motivo = NULLIF(LTRIM(RTRIM(@inMotivo)), N'');
        SET @numeroPedido = CAST(@inIdPedido AS NVARCHAR(12));

        -- validaciones
        -- GP016 restricción 1: solo la administradora
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
                AND (U.EsAdministrador = @true)
                AND (U.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50034; -- no es la administradora (mismo código que usa el backend)
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Pedido AS P
            WHERE (P.IdPedido = @inIdPedido)
        )
        BEGIN
            SET @outResultCode = 50056; -- el pedido no existe
            RETURN;
        END;

        SELECT @nombreEstado = EP.Nombre
            , @requiereMotivo = EP.FlagRequiereMotivo
            , @devuelveInventario = EP.FlagDevuelveInventario
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        IF (@nombreEstado IS NULL)
        BEGIN
            SET @outResultCode = 50057; -- cambio de estado no permitido
            RETURN;
        END;

        -- GP016 restricción 3: para rechazar es obligatorio el motivo
        IF (@requiereMotivo = @true)
            AND (@motivo IS NULL)
        BEGIN
            SET @outResultCode = 50058; -- falta el motivo
            RETURN;
        END;

        BEGIN TRANSACTION tCambiarEstadoPedido;

            -- bloquea el pedido y lee su estado actual
            SELECT @estadoActual = P.IdEstadoPedido
                , @idCliente = P.IdUsuario
                , @requiereDireccion = ME.FlagRequiereDireccion
            FROM dbo.Pedido AS P WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.MetodoEntrega AS ME
                ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
            WHERE (P.IdPedido = @inIdPedido);

            -- GP017 criterio 1: solo transiciones válidas
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.TransicionEstadoPedido AS TE
                WHERE (TE.IdEstadoActual = @estadoActual)
                    AND (TE.IdEstadoNuevo = @inIdEstadoNuevo)
                    AND (
                        (TE.FlagSoloEnvio = @false)
                        OR (@requiereDireccion = @true)
                    )
                    AND (
                        (TE.FlagSoloRetiro = @false)
                        OR (@requiereDireccion = @false)
                    )
            )
            BEGIN
                ROLLBACK TRANSACTION;
                SET @outResultCode = 50057; -- cambio de estado no permitido
                RETURN;
            END;

            -- Rechazado o Cancelado: los productos vuelven al inventario
            IF (@devuelveInventario = @true)
            BEGIN
                UPDATE PT
                SET PT.Cantidad = PT.Cantidad + D.Cantidad
                FROM dbo.ProductoTalla AS PT
                INNER JOIN (
                    SELECT PD.IdProductoTalla
                        , SUM(PD.Cantidad) AS Cantidad
                    FROM dbo.PedidoDetalle AS PD
                    WHERE (PD.IdPedido = @inIdPedido)
                    GROUP BY PD.IdProductoTalla
                ) AS D
                    ON (D.IdProductoTalla = PT.IdProductoTalla);

                INSERT INTO @productosDevueltos (
                    IdProducto
                )
                SELECT DISTINCT PT.IdProducto
                FROM dbo.PedidoDetalle AS PD
                INNER JOIN dbo.ProductoTalla AS PT
                    ON (PT.IdProductoTalla = PD.IdProductoTalla)
                WHERE (PD.IdPedido = @inIdPedido);
            END;

            UPDATE dbo.Pedido
            SET IdEstadoPedido = @inIdEstadoNuevo
                , MotivoEstado = COALESCE(@motivo, MotivoEstado)
            WHERE (IdPedido = @inIdPedido);

            -- GP016 paso 2.1 / GP017 paso 4.1: registra fecha y hora del cambio
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
                , FechaHora
            )
            VALUES (
                @inIdPedido
                , @inIdEstadoNuevo
                , @inIdUsuario
                , @motivo
                , GETDATE()
            );

            -- GP019: número de pedido, nuevo estado y motivo si lo hay; sin datos
            -- sensibles (restricción 3). El backend la envía por correo
            INSERT INTO dbo.Notificacion (
                IdPedido
                , Correo
                , Asunto
                , Mensaje
                , FlagEnviado
                , Intentos
                , FechaCreacion
            )
            SELECT @inIdPedido
                , U.Correo
                , N'Pedido #' + @numeroPedido + N': ' + @nombreEstado
                , N'Hola ' + U.Nombre + N', su pedido #' + @numeroPedido
                    + N' en Confecciones Capanni cambió al estado "' + @nombreEstado + N'".'
                    + CASE
                        WHEN (@motivo IS NOT NULL) THEN N' Motivo: ' + @motivo
                        ELSE N''
                      END
                , @false
                , @sinIntentos
                , GETDATE()
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @idCliente);

            SET @idNotificacion = SCOPE_IDENTITY();

        COMMIT TRANSACTION tCambiarEstadoPedido;

        -- primer resultado: el cambio hecho y la notificación por enviar
        SELECT @inIdPedido AS IdPedido
            , @inIdEstadoNuevo AS IdEstadoPedido
            , @nombreEstado AS Estado
            , @idCliente AS IdCliente
            , @idNotificacion AS IdNotificacion;

        -- segundo resultado: productos devueltos al inventario (vacío si no aplica),
        -- para avisarCatalogo (CP010)
        SELECT PD.IdProducto
        FROM @productosDevueltos AS PD;

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
