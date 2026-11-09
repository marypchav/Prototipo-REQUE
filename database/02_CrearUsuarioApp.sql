/*
Crea el usuario con el que el backend (Node) se conecta a SQL Server.
Se ejecuta DESPUÉS de BDCapanni_Instalar.sql.

Antes de ejecutar: cambie 'Capanni2026!' por la contraseña que quiera y
ponga esa misma en DB_PASSWORD del archivo backend/.env.

Se puede ejecutar varias veces: solo crea lo que falte.
El usuario únicamente puede EJECUTAR procedimientos: no puede leer ni
modificar las tablas directamente.
*/
USE master;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.server_principals AS SP
    WHERE (SP.name = 'capanni_app')
)
BEGIN
    CREATE LOGIN capanni_app WITH PASSWORD = 'Capanni2026!', CHECK_POLICY = OFF;
END;
GO

-- si el login ya existía y quiere cambiarle la contraseña, use:
-- ALTER LOGIN capanni_app WITH PASSWORD = 'NuevaContraseña';

USE BDCapanni;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals AS DP
    WHERE (DP.name = 'capanni_app')
)
BEGIN
    CREATE USER capanni_app FOR LOGIN capanni_app;
END;
GO

GRANT EXECUTE TO capanni_app;
GO
