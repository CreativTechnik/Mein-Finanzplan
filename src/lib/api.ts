import type { Snapshot } from "../types";

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: init?.body ? { "Content-Type": "application/json", ...init.headers } : init?.headers,
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error ?? `Anfrage fehlgeschlagen (${response.status}).`);
  }
  if (response.status === 204) return undefined as T;
  return response.json();
}

export const api = {
  snapshot: () => request<Snapshot>("/api/bootstrap?days=90"),
  create: <T>(resource: string, body: unknown) => request<T>(`/api/${resource}`, { method: "POST", body: JSON.stringify(body) }),
  update: <T>(resource: string, id: string, body: unknown) => request<T>(`/api/${resource}/${id}`, { method: "PUT", body: JSON.stringify(body) }),
  remove: (resource: string, id: string) => request<void>(`/api/${resource}/${id}`, { method: "DELETE" }),
  upsertBudget: (body: unknown) => request("/api/budgets", { method: "PUT", body: JSON.stringify(body) }),
  importCsv: (rows: unknown[]) => request<{ imported: number }>("/api/import/csv", { method: "POST", body: JSON.stringify({ rows }) }),
};
