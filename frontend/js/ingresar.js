/* =====================================================================
   GI001 Inicio de sesión de la administradora: /admin/ingresar.html
   Si el acceso es exitoso, cambia a la página del inventario
   (o a la página de administración que intentaba abrir).
   ===================================================================== */

const form = document.getElementById('formIngreso');
const correo = document.getElementById('correo');
const contrasena = document.getElementById('contrasena');
const errorIngreso = document.getElementById('errorIngreso');
const botonIngresar = document.getElementById('botonIngresar');
const verClave = document.getElementById('verClave');

// solo se acepta volver a una página de /admin de este mismo sitio
function paginaDeDestino() {
  const volver = new URLSearchParams(location.search).get('volver') || '';
  return /^\/admin\/[\w\-./?=&%]*$/.test(volver) && !volver.startsWith('/admin/ingresar')
    ? volver
    : '/admin/inventario.html';
}

function mostrarError(texto) {
  errorIngreso.textContent = texto;
  errorIngreso.hidden = false;
}

verClave.addEventListener('click', () => {
  const mostrar = contrasena.type === 'password';
  contrasena.type = mostrar ? 'text' : 'password';
  verClave.textContent = mostrar ? 'Ocultar' : 'Mostrar';
  verClave.setAttribute('aria-pressed', String(mostrar));
});

form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  errorIngreso.hidden = true;
  correo.removeAttribute('aria-invalid');
  contrasena.removeAttribute('aria-invalid');

  if (!correo.value.trim() || !contrasena.value) {
    if (!correo.value.trim()) correo.setAttribute('aria-invalid', 'true');
    if (!contrasena.value) contrasena.setAttribute('aria-invalid', 'true');
    mostrarError('Complete todos los campos obligatorios.');
    (correo.value.trim() ? contrasena : correo).focus();
    return;
  }

  botonIngresar.disabled = true;
  botonIngresar.textContent = 'Iniciando sesión…';

  try {
    await api('/sesion', {
      metodo: 'POST',
      cuerpo: { correo: correo.value.trim(), contrasena: contrasena.value },
    });
    location.replace(paginaDeDestino());
  } catch (error) {
    // GI001 alterno: el mismo mensaje sin decir cuál dato falló
    mostrarError(error.message);
    contrasena.value = '';
    contrasena.focus();
    botonIngresar.disabled = false;
    botonIngresar.textContent = 'Iniciar sesión';
  }
});

// si ya tiene la sesión de administradora abierta, pasa directo
// (con una sesión de cliente se queda aquí para iniciar como administradora)
api('/sesion')
  .then(({ datos }) => {
    if (datos?.esAdministrador) location.replace(paginaDeDestino());
  })
  .catch(() => {});

correo.focus();
