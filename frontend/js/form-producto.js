/* =====================================================================
   Formulario de producto: /admin/producto.html        (agregar, GI002)
                           /admin/producto.html?id=5   (modificar, GI005)
   La foto (GI003) se sube después de guardar los datos, con el id del producto.
   ===================================================================== */

const TIPOS_FOTO = ['image/png', 'image/jpeg'];
const MAX_FOTO = 5 * 1024 * 1024; // 5 MB, igual que el backend

const MENSAJES = {
  obligatorios: 'Complete todos los campos obligatorios.',
  precio: 'El precio debe ser un número mayor que cero.',
  cantidades: 'Las cantidades deben ser números enteros, sin decimales, letras ni valores negativos.',
  ningunaTalla: 'Ingrese existencias en al menos una talla.',
  tipoFoto: 'Solo se permiten imágenes PNG o JPG.',
  pesoFoto: 'La imagen no puede superar los 5 MB.',
};

let idProducto = Number(new URLSearchParams(location.search).get('id')) || null;
let fotoNueva = null; // File elegido, todavía sin subir
let urlVistaPrevia = null;
let rutaFotoActual = null;

const el = {
  titulo: document.getElementById('tituloForm'),
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoForm'),
  form: document.getElementById('formProducto'),
  error: document.getElementById('errorForm'),
  nombre: document.getElementById('nombre'),
  categoria: document.getElementById('categoria'),
  precio: document.getElementById('precio'),
  descripcion: document.getElementById('descripcion'),
  contador: document.getElementById('contadorDescripcion'),
  tallas: document.getElementById('camposTallas'),
  vistaFoto: document.getElementById('vistaFoto'),
  fotoCamara: document.getElementById('fotoCamara'),
  fotoGaleria: document.getElementById('fotoGaleria'),
  quitarFoto: document.getElementById('quitarFoto'),
  guardar: document.getElementById('guardar'),
};

/* ---------------- Cargar ---------------- */

async function iniciar() {
  const usuario = await exigirSesion('inventario');
  if (!usuario) return;

  try {
    const { datos: opciones } = await api('/admin/opciones-producto');
    pintarCategorias(opciones.categorias ?? []);

    if (idProducto) {
      const { datos: producto } = await api('/admin/productos/' + idProducto);
      ponerModoModificar(producto.Nombre);
      llenarFormulario(producto);
    } else {
      pintarTallas((opciones.tallas ?? []).map((t) => ({ IdTalla: t.IdTalla, Talla: t.Nombre, Cantidad: 0 })));
      pintarVistaFoto();
    }

    el.form.hidden = false;
    el.nombre.focus();
  } catch (error) {
    if (error.codigo === 50033) return;
    el.estado.innerHTML = `
      <div class="vacio">
        <h2>${error.codigo === 50011 ? 'Este producto ya no está disponible' : 'No se pudo cargar el formulario'}</h2>
        <p>${error.codigo === 50011 ? 'Puede que lo hayan eliminado.' : escapar(error.message)}</p>
        <a class="boton boton-principal" href="/admin/inventario.html">Volver al inventario</a>
      </div>`;
  } finally {
    el.cargando.hidden = true;
  }
}

function ponerModoModificar(nombre) {
  el.titulo.textContent = 'Modificar producto';
  document.title = `Modificar ${nombre} | Capanni`;
  el.guardar.textContent = 'Guardar cambios';
}

function pintarCategorias(categorias) {
  el.categoria.innerHTML =
    '<option value="">Seleccione una categoría</option>' +
    categorias.map((c) => `<option value="${c.IdCategoria}">${escapar(c.Nombre)}</option>`).join('');
}

function pintarTallas(tallas) {
  el.tallas.innerHTML = tallas
    .map(
      (t) => `<div class="talla-existencia">
        <label for="talla-${t.IdTalla}" class="talla">${escapar(t.Talla)}</label>
        <input type="text" inputmode="numeric" id="talla-${t.IdTalla}" data-talla="${t.IdTalla}"
               value="${Number(t.Cantidad) || 0}" autocomplete="off" aria-label="Cantidad en talla ${escapar(t.Talla)}">
      </div>`
    )
    .join('');
}

function llenarFormulario(p) {
  el.nombre.value = p.Nombre ?? '';
  el.categoria.value = String(p.IdCategoria ?? '');
  el.precio.value = p.Precio ?? '';
  el.descripcion.value = p.Descripcion ?? '';
  el.contador.textContent = el.descripcion.value.length;
  el.form.className = `form-producto tarjeta-form ${claseCategoria(p.IdCategoria)}`;
  rutaFotoActual = p.RutaImagen ?? null;
  pintarTallas(p.tallas ?? []);
  pintarVistaFoto();
}

/* ---------------- Foto (GI003) ---------------- */

function pintarVistaFoto() {
  if (fotoNueva) {
    el.vistaFoto.innerHTML = `<img src="${urlVistaPrevia}" alt="Vista previa de la foto nueva">`;
  } else if (rutaFotoActual) {
    el.vistaFoto.innerHTML = htmlFoto({ RutaImagen: rutaFotoActual, Nombre: 'Foto actual' }, { textoSinFoto: 'Sin foto' });
  } else {
    el.vistaFoto.innerHTML = htmlSinFoto('Sin foto');
  }
  el.quitarFoto.hidden = !fotoNueva;
}

function elegirFoto(evento) {
  const archivo = evento.target.files?.[0];
  evento.target.value = ''; // permite volver a elegir el mismo archivo
  if (!archivo) return;

  // GI003 alterno: imagen no compatible
  if (!TIPOS_FOTO.includes(archivo.type)) return mostrarError(MENSAJES.tipoFoto);
  if (archivo.size > MAX_FOTO) return mostrarError(MENSAJES.pesoFoto);

  ocultarError();
  if (urlVistaPrevia) URL.revokeObjectURL(urlVistaPrevia);
  fotoNueva = archivo;
  urlVistaPrevia = URL.createObjectURL(archivo);
  pintarVistaFoto();
}

// los botones [data-abrir] (Tomar foto, Elegir de la galería) los maneja comun.js
el.fotoCamara.addEventListener('change', elegirFoto);
el.fotoGaleria.addEventListener('change', elegirFoto);
el.quitarFoto.addEventListener('click', () => {
  if (urlVistaPrevia) URL.revokeObjectURL(urlVistaPrevia);
  fotoNueva = null;
  urlVistaPrevia = null;
  pintarVistaFoto();
});

/* ---------------- Validar ---------------- */

function mostrarError(texto, campo) {
  el.error.textContent = texto;
  el.error.hidden = false;
  if (campo) {
    campo.setAttribute('aria-invalid', 'true');
    campo.focus();
  } else {
    el.error.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }
}

function ocultarError() {
  el.error.hidden = true;
  el.form.querySelectorAll('[aria-invalid]').forEach((c) => c.removeAttribute('aria-invalid'));
}

el.descripcion.addEventListener('input', () => {
  el.contador.textContent = el.descripcion.value.length;
});

// GI002 alterno: el registro no continúa si hay campos vacíos o cantidades inválidas
function leerFormulario() {
  ocultarError();

  const nombre = el.nombre.value.trim();
  const idCategoria = el.categoria.value;
  const textoPrecio = el.precio.value.trim().replace(/\s/g, '').replace(',', '.');

  if (!nombre) return mostrarError(MENSAJES.obligatorios, el.nombre);
  if (!idCategoria) return mostrarError(MENSAJES.obligatorios, el.categoria);
  if (!textoPrecio) return mostrarError(MENSAJES.obligatorios, el.precio);

  const precio = Number(textoPrecio);
  if (!/^\d+(\.\d{1,2})?$/.test(textoPrecio) || !(precio > 0)) {
    return mostrarError(MENSAJES.precio, el.precio);
  }

  const tallas = [];
  for (const campo of el.tallas.querySelectorAll('input[data-talla]')) {
    const texto = campo.value.trim() || '0';
    if (!/^\d+$/.test(texto)) return mostrarError(MENSAJES.cantidades, campo);
    tallas.push({ idTalla: Number(campo.dataset.talla), cantidad: Number(texto) });
  }

  if (!idProducto && !tallas.some((t) => t.cantidad > 0)) {
    return mostrarError(MENSAJES.ningunaTalla, el.tallas.querySelector('input'));
  }

  return {
    nombre,
    descripcion: el.descripcion.value.trim() || null,
    idCategoria: Number(idCategoria),
    precio,
    tallas,
  };
}

/* ---------------- Guardar ---------------- */

el.form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const datos = leerFormulario();
  if (!datos) return;

  const textoBoton = el.guardar.textContent;
  el.guardar.disabled = true;
  el.guardar.textContent = 'Guardando…';

  let mensaje;
  try {
    if (idProducto) {
      ({ mensaje } = await api('/admin/productos/' + idProducto, { metodo: 'PUT', cuerpo: datos }));
    } else {
      const respuesta = await api('/admin/productos', { metodo: 'POST', cuerpo: datos });
      mensaje = respuesta.mensaje;
      idProducto = respuesta.datos.idProducto;
      // si la foto falla, el formulario ya queda en modo modificar
      history.replaceState(null, '', '/admin/producto.html?id=' + idProducto);
      ponerModoModificar(datos.nombre);
    }
  } catch (error) {
    if (error.codigo !== 50033) mostrarError(error.message);
    el.guardar.disabled = false;
    el.guardar.textContent = textoBoton;
    return;
  }

  if (fotoNueva) {
    try {
      const formulario = new FormData();
      formulario.append('foto', fotoNueva);
      await api(`/admin/productos/${idProducto}/foto`, { metodo: 'POST', formulario });
      mensaje += ' La foto fue guardada.';
    } catch (error) {
      mostrarError(`Los datos se guardaron, pero la foto no: ${error.message}`);
      el.guardar.disabled = false;
      el.guardar.textContent = 'Guardar cambios';
      return;
    }
  }

  avisarEnSiguientePagina(mensaje || 'Los cambios fueron guardados.');
  location.assign('/admin/inventario.html');
});

iniciar();
