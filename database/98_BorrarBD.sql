/*
Borra la base BDCapanni COMPLETA (tablas, datos y procedimientos) para
volver a instalarla desde cero con BDCapanni_Instalar.sql.

CUIDADO: se pierden todos los datos. No toca el login capanni_app (ese es
del servidor, no de la base), pero sí borra su usuario dentro de la base:
después de reinstalar hay que ejecutar 02_CrearUsuarioApp.sql otra vez.
*/
USE master;
GO

IF (DB_ID('BDCapanni') IS NOT NULL)
BEGIN
    -- desconecta a quien esté usando la base (SSMS, el backend) para poder borrarla
    ALTER DATABASE BDCapanni SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BDCapanni;
END;
GO
