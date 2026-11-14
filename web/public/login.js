// The login page: the part of the address after "#" never reaches the server, so it is added to the page asked
// for here, and a route link (#/routes/add?r=…) still opens after logging in.
document.querySelector("form")?.addEventListener("submit", (e) => {
  const next = e.currentTarget.elements.namedItem("next");
  if (next && location.hash && !next.value.includes("#")) next.value += location.hash;
});
