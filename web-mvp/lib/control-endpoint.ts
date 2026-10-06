// Keep the session cookie same-site when the desk is opened using localhost.
export const CONTROL_API = typeof window !== "undefined" && window.location.hostname === "localhost"
  ? "http://localhost:4321" : "http://127.0.0.1:4321";
