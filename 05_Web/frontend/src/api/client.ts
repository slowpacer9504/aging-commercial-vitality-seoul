// Typed fetch wrapper. Throws ApiError with code on non-2xx.
import type { ApiErrorDetail } from "@/types/api";

export class ApiError extends Error {
  readonly code: string;
  readonly hint: string | null;
  readonly status: number;
  constructor(code: string, message: string, status: number, hint: string | null = null) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.hint = hint;
    this.status = status;
  }
}

async function readError(res: Response): Promise<ApiError> {
  let code = "http_error";
  let detail = `${res.status} ${res.statusText}`;
  let hint: string | null = null;
  try {
    const body = (await res.json()) as ApiErrorDetail | { detail?: string };
    if (body && typeof body === "object" && "detail" in body) {
      const d = body.detail;
      if (typeof d === "object" && d !== null && "code" in d) {
        code = (d as { code: string }).code;
        detail = (d as { detail: string }).detail;
        hint = (d as { hint?: string | null }).hint ?? null;
      } else if (typeof d === "string") {
        detail = d;
      }
    }
  } catch {
    // Keep default values if response is not JSON.
  }
  return new ApiError(code, detail, res.status, hint);
}

export async function getJSON<T>(path: string, signal?: AbortSignal): Promise<T> {
  const res = await fetch(path, {
    method: "GET",
    headers: { Accept: "application/json" },
    signal,
  });
  if (!res.ok) throw await readError(res);
  return (await res.json()) as T;
}
