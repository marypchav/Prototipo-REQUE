# Sistema de Catálogo en Línea y Pedidos — Confecciones Capanni

Proyecto del curso IC5821 Requerimientos de Software, TEC.
Mary Paz Chavarría Castillo y Gabriel Sánchez Acuña.

## Estructura

```
capanni/
├── .gitignore             qué NO se sube a git
├── .gitattributes         finales de línea iguales en Windows y Mac
├── README.md              esta guía
├── database/              base de datos BDCapanni (SQL Server)
│   ├── 00_CrearTablas.sql
│   ├── 01_CargarCatalogos.sql
│   ├── fn/  tr/  sp/      funciones, trigger y procedimientos
│   ├── BDCapanni_Instalar.sql   todo lo anterior en un solo archivo
│   ├── 99_PruebaFlujo.sql       prueba de punta a punta
│   └── CodigosError.md
├── backend/               API en Node.js + Express
│   ├── package.json       dependencias y comandos
│   ├── .env.example       plantilla de configuración (el .env real NO se sube)
│   ├── pruebas.http       pruebas de la API desde VS Code
│   ├── scripts/
│   │   └── generarHash.js contraseña de la administradora
│   ├── uploads/           fotos y comprobantes (se llena sola, no se sube)
│   └── src/
│       ├── server.js      arranca el servidor
│       ├── app.js         configura Express
│       ├── config/        lee el .env
│       ├── db/            conexión y ejecutarSP (única forma de usar la BD)
│       ├── middlewares/   sesión, permisos, subida de imágenes, errores
│       ├── controllers/   qué hace cada ruta
│       ├── routes/        qué URL va a cada controller
│       └── utils/         códigos de error y conversiones
└── frontend/              páginas web (siguiente paso)
```

Cómo viaja una petición:

```
navegador → routes → middlewares (sesión/permisos) → controller → ejecutarSP → SP en SQL Server
                                                                   ↓
navegador ← { ok, datos } o { ok: false, codigo, mensaje } ← manejarErrores
```

> **Para instalar desde cero, siga `INSTALACION.md`.** Esta guía explica el proyecto con más detalle.

## Requisitos

- Node.js 18 o superior (`node --version`)
- SQL Server con la base BDCapanni ya creada (carpeta `database`)
- VS Code con la extensión REST Client (para `pruebas.http`)

## Instalación paso a paso

### 1. SQL Server: permitir que Node se conecte

Node se conecta por red con usuario y contraseña de SQL Server (no con el usuario de Windows).

1. **Activar autenticación mixta:** en SSMS, clic derecho al servidor → Propiedades → Seguridad → "Modo de autenticación de SQL Server y Windows". Reinicie el servicio de SQL Server.
2. **Activar TCP/IP:** abra "SQL Server Configuration Manager" → Configuración de red de SQL Server → Protocolos → TCP/IP → Habilitar. Reinicie el servicio.
   - Si usa **SQL Server Express**, en TCP/IP → Direcciones IP → IPAll ponga `TCP Port = 1433` y deje vacío "Puertos dinámicos". Así funciona con `DB_PORT=1433` sin `DB_INSTANCE`.
3. **Crear el usuario de la aplicación** (en SSMS, cambie la contraseña):

```sql
USE master;
CREATE LOGIN capanni_app WITH PASSWORD = 'CambieEstaContrasena123!', CHECK_POLICY = OFF;
USE BDCapanni;
CREATE USER capanni_app FOR LOGIN capanni_app;
GRANT EXECUTE TO capanni_app;   -- solo puede ejecutar SP, no tocar tablas directo
```

### 2. Backend

En una terminal, dentro de la carpeta `backend`:

```bash
npm install
```

Copie `.env.example` como `.env` (en la misma carpeta) y llene sus valores. Para el `JWT_SECRET`:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
```

### 3. Contraseña de la administradora

```bash
npm run hash -- "LaContraseñaDeCarmen"
```

Copie el `UPDATE` que imprime y ejecútelo en SSMS.

### 4. Arrancar

```bash
npm run dev
```

Debe decir `Conectado a SQL Server` y `Servidor listo en http://localhost:3000`.

### 5. Probar

Abra `backend/pruebas.http` en VS Code y ejecute las peticiones en orden (primero el login).

## Errores comunes al arrancar

| Mensaje | Causa | Solución |
|---|---|---|
| `Faltan variables en el archivo .env` | No existe el `.env` o le falta algo | Copie `.env.example` como `.env` |
| `Login failed for user` | Usuario o contraseña de SQL mal, o autenticación mixta apagada | Paso 1.1 y 1.3 |
| `Failed to connect to localhost:1433` | TCP/IP apagado o puerto distinto | Paso 1.2 |
| `Could not find stored procedure` | No se ejecutaron los scripts de `database` | Ejecute `BDCapanni_Instalar.sql` |
| `The EXECUTE permission was denied` | Falta el `GRANT EXECUTE` | Paso 1.3 |

## Rutas de la API

La lista completa, con el requerimiento de la ERS de cada una, está al inicio de `backend/src/routes/index.js`.

## Correos (GP019)

Sin configurar nada, los correos se **imprimen en la terminal** del servidor con el texto `[correo simulado]` y quedan marcados como enviados. Para enviarlos de verdad con Gmail:

1. Active la verificación en 2 pasos en la cuenta de Google.
2. Cree una contraseña de aplicación en https://myaccount.google.com/apppasswords
3. En el `.env`:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=sucorreo@gmail.com
SMTP_PASS=la_contraseña_de_aplicación_de_16_letras
SMTP_FROM="Confecciones Capanni <sucorreo@gmail.com>"
```

## Tiempo real (CP010)

El servidor avisa a los navegadores con Socket.IO. En el frontend:

```html
<script src="/socket.io/socket.io.js"></script>
<script>
  const socket = io();
  socket.on('catalogo:actualizado', () => cargarCatalogo());         // todos
  socket.on('pedido:nuevo', ({ idPedido }) => avisarNuevoPedido());   // administradora
  socket.on('pedido:estado', ({ idPedido, estado }) => recargar());   // cliente dueño
</script>
```

## Formato de respuestas

Éxito: `{ "ok": true, "datos": ..., "mensaje": "..." }`
Error: `{ "ok": false, "codigo": 50008, "mensaje": "El precio debe ser mayor que cero." }`

El frontend solo tiene que mostrar `mensaje`. La lista de códigos está en `database/CodigosError.md`.

## Git: cómo trabajar los dos

Primera vez (lo hace una sola persona):

```bash
cd capanni
git init
git add .
git status            # revise que NO aparezcan .env ni node_modules
git commit -m "Base de datos y estructura inicial del backend"
git branch -M main
git remote add origin https://github.com/USUARIO/capanni.git
git push -u origin main
```

La otra persona:

```bash
git clone https://github.com/USUARIO/capanni.git
cd capanni/backend
npm install
# crear su propio .env a partir de .env.example
```

Día a día:

```bash
git pull                          # antes de empezar
git checkout -b cu2-carrito       # una rama por caso de uso
# ... trabajar ...
git add .
git commit -m "CU2: rutas del carrito"
git push -u origin cu2-carrito    # y en GitHub se abre un Pull Request a main
```

Qué nunca se sube (ya lo cubre el `.gitignore`): `node_modules/`, `.env`, las imágenes de `backend/uploads/`.
Cada uno tiene su propio `.env` con los datos de su SQL Server.
