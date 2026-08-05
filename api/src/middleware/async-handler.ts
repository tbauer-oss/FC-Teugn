import {
  NextFunction,
  Request,
  RequestHandler,
  Response,
  Router,
} from 'express';

type AsyncRouteHandler = (
  req: Request,
  res: Response,
  next: NextFunction,
) => unknown | Promise<unknown>;

export function asyncHandler(handler: AsyncRouteHandler): RequestHandler {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

const registrationMethods = new Set([
  'use',
  'get',
  'post',
  'put',
  'patch',
  'delete',
  'options',
  'head',
]);

function wrapRegistrationArgument(argument: unknown): unknown {
  if (Array.isArray(argument)) {
    return argument.map(wrapRegistrationArgument);
  }
  if (typeof argument !== 'function' || argument.length === 4) {
    return argument;
  }
  return asyncHandler(argument as AsyncRouteHandler);
}

/**
 * Express 4 does not forward rejected route promises to error middleware.
 * Every route registered through this router is therefore wrapped once at
 * registration time. Database failures now produce an immediate structured
 * response instead of leaving the browser waiting until its own timeout.
 */
export function asyncRouter(): Router {
  const router = Router();
  for (const method of registrationMethods) {
    const register = (router as unknown as Record<string, Function>)[method]
      .bind(router);
    (router as unknown as Record<string, Function>)[method] = (
      ...arguments_: unknown[]
    ) => register(...arguments_.map(wrapRegistrationArgument));
  }
  return router;
}
