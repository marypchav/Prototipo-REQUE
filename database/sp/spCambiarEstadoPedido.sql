CREATE OR ALTER PROCEDURE dbo.spCambiarEstadoPedido
    @inIdUsuario INT -- quién cambia el estado, debe ser administradora
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdPedido INT -- pedido
    , @inIdEstadoNuevo INT -- estado al que pasa
    , @inMotivo NVARCHAR(300) -- obligatorio para Rechazado y Cancelado
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
GP016 Confirmar o rechazar pedido, GP017 Actualizar estado de pedido y
GP019 Notificar al cliente.

Un solo SP para todos los cambios de estado porque las reglas vienen de
las tablas de catálogo, no del código:
    - TransicionEstadoPedido dice a qué estado se puede pasar (solo avanzan)
    - EstadoPedido.FlagRequiereMotivo pide el motivo (Rechazado, Cancelado)
    - EstadoPedido.FlagDevuelveInventario regresa las existencias

La notificación queda en la tabla Notificacion; el backend la envía por
correo y la marca con spMarcarNotificacion.

Ejemplo de ejecución (confirmar):
    DECLARE @resultado INT;

    EXEC dbo.spCambiarEstadoPedido
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @inIdPedido = 1
        , @inIdEstadoNuevo = 2
        , @inMotivo = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEstado INT = 11; -- "Cambiar estado de pedido"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idEstadoActual INT
            , @idCliente INT
            , @requiereDireccion BIT
            , @requiereMotivo BIT
            , @devuelveInventario BIT
            , @transicionValida BIT
            , @motivo NVARCHAR(300);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idEstadoActual = NULL;
        SET @requiereMotivo = NULL;
        SET @transicionValida = @false;
        SET @motivo = NULLIF(LTRIM(RTRIM(@inMotivo)), N'');

        -- validaciones
        -- GP016 restricción 1: solo la administradora
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario)
            AND (U.FlagActivo = @true);

        IF (@esAdministrador = @false)
        BEGIN
            SET @outResultCode = 50002; -- requiere rol de administración
            RETURN;
        END;

        SELECT @idEstadoActual = P.IdEstadoPedido
            , @idCliente = P.IdUsuario
            , @requiereDireccion = ME.FlagRequiereDireccion
        FROM dbo.Pedido AS P
        INNER JOIN dbo.MetodoEntrega AS ME
            ON (ME.IdMetodoEntrega = P.IdMetodoEntrega)
        WHERE (P.IdPedido = @inIdPedido);

        IF (@idEstadoActual IS NULL)
        BEGIN
            SET @outResultCode = 50024; -- pedido no existe
            RETURN;
        END;

        SELECT @requiereMotivo = EP.FlagRequiereMotivo
            , @devuelveInventario = EP.FlagDevuelveInventario
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        -- GP017 restricción 2: la transición debe estar permitida para el
        -- estado actual y para el tipo de entrega (envío o retiro)
        SELECT @transicionValida = @true
        FROM dbo.TransicionEstadoPedido AS TEP
        WHERE (TEP.IdEstadoActual = @idEstadoActual)
            AND (TEP.IdEstadoNuevo = @inIdEstadoNuevo)
            AND (
                (TEP.FlagSoloEnvio = @false)
                OR (@requiereDireccion = @true)
            )
            AND (
                (TEP.FlagSoloRetiro = @false)
                OR (@requiereDireccion = @false)
            );

        IF (@requiereMotivo IS NULL)
            OR (@transicionValida = @false)
        BEGIN
            SET @outResultCode = 50025; -- transición de estado no permitida
            RETURN;
        END;

        -- GP016 restricción 3: rechazar (y cancelar) exige motivo
        IF (@requiereMotivo = @true)
            AND (@motivo IS NULL)
        BEGIN
            SET @outResultCode = 50026; -- falta el motivo
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @nombreEstadoActual NVARCHAR(32)
            , @nombreEstadoNuevo NVARCHAR(32)
            , @nombreCliente NVARCHAR(100)
            , @correoCliente VARCHAR(128)
            , @asunto NVARCHAR(128)
            , @mensaje NVARCHAR(600)
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SELECT @nombreEstadoActual = EP.Nombre
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @idEstadoActual);

        SELECT @nombreEstadoNuevo = EP.Nombre
        FROM dbo.EstadoPedido AS EP
        WHERE (EP.IdEstadoPedido = @inIdEstadoNuevo);

        SELECT @nombreCliente = U.Nombre
            , @correoCliente = U.Correo
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @idCliente);

        -- GP019 restricción 1: número de pedido, nuevo estado y motivo si aplica.
        -- restricción 3: sin datos sensibles
        SET @asunto = CONCAT(N'Pedido #', @inIdPedido, N': ', @nombreEstadoNuevo);
        SET @mensaje = LEFT(CONCAT(
                N'Hola ', @nombreCliente
                , N'. Su pedido #', @inIdPedido
                , N' cambió al estado "', @nombreEstadoNuevo, N'".'
                , CASE
                    WHEN (@motivo IS NOT NULL) THEN CONCAT(N' Motivo: ', @motivo)
                    ELSE N''
                  END
                , N' Gracias por comprar en Confecciones Capanni.'
            ), 600);

        SET @jsonAntes = (
            SELECT @inIdPedido AS IdPedido
                , @nombreEstadoActual AS Estado
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        SET @jsonDespues = (
            SELECT @inIdPedido AS IdPedido
                , @nombreEstadoNuevo AS Estado
                , @motivo AS Motivo
                , @devuelveInventario AS DevuelveInventario
            FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
        );

        -- transacción: estado, inventario, historial, notificación y
        -- bitácora se guardan juntos o nada
        BEGIN TRANSACTION tCambiarEstadoPedido;

            -- el WHERE con el estado actual evita aplicar dos veces el mismo
            -- cambio (por ejemplo, doble clic en "Rechazar", que devolvería
            -- el inventario dos veces)
            UPDATE dbo.Pedido
            SET IdEstadoPedido = @inIdEstadoNuevo
                , MotivoEstado = CASE
                    WHEN (@motivo IS NOT NULL) THEN @motivo
                    ELSE MotivoEstado
                  END
            WHERE (IdPedido = @inIdPedido)
                AND (IdEstadoPedido = @idEstadoActual);

            IF (@@ROWCOUNT = 0)
            BEGIN
                ROLLBACK TRANSACTION tCambiarEstadoPedido;
                SET @outResultCode = 50025; -- otro proceso ya cambió el estado
                RETURN;
            END;

            -- Rechazado o Cancelado: regresan las existencias (GP016 alterno,
            -- GP017 restricción 3). Sin IF: el WHERE decide
            UPDATE PT
            SET Cantidad = PT.Cantidad + PD.Cantidad
            FROM dbo.ProductoTalla AS PT
            INNER JOIN dbo.PedidoDetalle AS PD
                ON (PD.IdProductoTalla = PT.IdProductoTalla)
            WHERE (PD.IdPedido = @inIdPedido)
                AND (@devuelveInventario = @true);

            -- historial con fecha y hora (GP016 paso 2.1, GP017 paso 4.1)
            INSERT INTO dbo.HistorialEstadoPedido (
                IdPedido
                , IdEstadoPedido
                , IdUsuario
                , Comentario
            )
            VALUES (
                @inIdPedido
                , @inIdEstadoNuevo
                , @inIdUsuario
                , @motivo
            );

            -- notificación pendiente de envío (GP019)
            INSERT INTO dbo.Notificacion (
                IdPedido
                , Correo
                , Asunto
                , Mensaje
            )
            VALUES (
                @inIdPedido
                , @correoCliente
                , @asunto
                , @mensaje
            );

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEstado
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tCambiarEstadoPedido;

        -- resultado para la capa lógica: a quién avisar en tiempo real y si
        -- el catálogo cambió (cuando se devuelven existencias)
        SELECT @idCliente AS IdUsuarioCliente
            , @nombreEstadoNuevo AS Estado
            , @devuelveInventario AS DevuelveInventario;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
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
