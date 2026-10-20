<?php

use App\Http\Middleware\EnsureEnabled;
use App\Http\Middleware\NormalizeLegacyInput;
use App\Http\Middleware\RequireMockPayments;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(web: __DIR__.'/../routes/web.php', commands: __DIR__.'/../routes/console.php', health: '/up')
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->web(append: [NormalizeLegacyInput::class]);
        $middleware->alias(['enabled' => EnsureEnabled::class, 'mock.payments' => RequireMockPayments::class]);
        $middleware->redirectGuestsTo('/login');
        $middleware->redirectUsersTo(fn (Request $r) => $r->user()?->isAdmin() ? '/admin' : '/dashboard');
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(fn (Request $r) => $r->is('api/*') || $r->expectsJson());
        $exceptions->render(function (ValidationException $e, Request $r) {
            if (! $r->is('api/*')) {
                return null;
            }
            $errors = [];
            foreach ($e->errors() as $field => $messages) {
                $field = ['restaurant_id' => 'restaurantId', 'table_number' => 'tableNumber'][$field] ?? $field;
                foreach ($messages as $message) {
                    $errors[] = compact('field', 'message');
                }
            }

            $code = 'VALIDATION_ERROR';
            if (! $r->exists('restaurant_id') || ! $r->exists('table_number')) {
                $code = 'MISSING_PARAMETER';
            } elseif (filter_var($r->input('table_number'), FILTER_VALIDATE_INT) === false) {
                $code = 'INVALID_PARAMETER_TYPE';
            }

            return response()->json(['code' => $code, 'message' => 'Параметры запроса заполнены неправильно', 'errors' => $errors], 400);
        });
        $exceptions->render(function (NotFoundHttpException $e, Request $r) {
            if ($r->is('api/v1/orders/current')) {
                return response()->json(['code' => 'ORDER_NOT_FOUND', 'message' => 'Активный заказ не найден'], 404);
            }

            return null;
        });
    })->create();
