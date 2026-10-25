export class ReportServiceError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string,
    readonly retryAfter?: number,
    readonly reportId?: string,
  ) {
    super(message);
  }
}
