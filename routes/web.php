<?php

use App\Http\Controllers\AdminController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\FreedomPayController;
use App\Http\Controllers\PaymentController;
use App\Http\Controllers\RestaurantController;
use App\Http\Controllers\TableController;
use App\Models\Payment;
use App\Models\RestaurantOrder;
use App\Services\OrderService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::view('/', 'home')->name('home');
Route::get('/api/v1/health', fn () => ['status' => 'UP', 'service' => 'procash']);
Route::get('/actuator/health', function () {
    try {
        DB::select('SELECT 1');

        return response()->json(['status' => 'UP']);
    } catch (Throwable $e) {
        report($e);

        return response()->json(['status' => 'DOWN'], 503);
    }
});
Route::middleware('guest')->group(function () {
    Route::view('/login', 'auth.login')->name('login');
    Route::post('/login', [AuthController::class, 'login'])->middleware('throttle:login');
    Route::view('/register', 'auth.register')->name('register');
    Route::post('/register', [AuthController::class, 'register'])->middleware('throttle:register');
});
Route::post('/logout', [AuthController::class, 'logout'])->middleware('auth')->name('logout');

Route::get('/r/{slug}/q/{token}', [TableController::class, 'publicTable'])->whereUuid('token')->name('tables.public');
Route::middleware('mock.payments')->group(function () {
    Route::post('/payments/create', [PaymentController::class, 'create'])->name('payments.create');
    Route::get('/payments/{payment}/mock', [PaymentController::class, 'mock'])->whereUuid('payment')->name('payments.mock');
    Route::post('/payments/{payment}/mock/success', [PaymentController::class, 'paid'])->whereUuid('payment');
    Route::post('/payments/{payment}/mock/fail', [PaymentController::class, 'failed'])->whereUuid('payment');
});
Route::get('/payments/{payment}/success', [PaymentController::class, 'success'])->whereUuid('payment')->name('payments.success');

$demo = function (Request $r, OrderService $service) {
    $data = $r->validate(['restaurant_id' => ['required', 'string', 'max:255'], 'table_number' => ['required', 'integer', 'min:1']]);

    return $service->demo($data['restaurant_id'], (int) $data['table_number']);
};
Route::get('/order', fn (Request $r, OrderService $s) => view('orders.demo', ['order' => $demo($r, $s)]));
Route::middleware(['auth', 'enabled'])->group(function () use ($demo) {
    Route::get('/api/v1/orders/current', $demo);
    Route::get('/dashboard', function (Request $r) {
        $ids = $r->user()->restaurants()->select('id');

        return view('dashboard', [
            'restaurants' => $r->user()->restaurants()->with('application')->latest()->get(),
            'orderCount' => RestaurantOrder::whereIn('restaurant_id', clone $ids)->whereDate('opened_at', today())->count(),
            'paidToday' => Payment::whereIn('restaurant_id', clone $ids)->where('status', 'PAID')->whereDate('paid_at', today())->sum('amount'),
        ]);
    })->name('dashboard');
    Route::get('/restaurants', [RestaurantController::class, 'index'])->name('restaurants.index');
    Route::get('/restaurants/new', [RestaurantController::class, 'create'])->name('restaurants.create');
    Route::post('/restaurants', [RestaurantController::class, 'store'])->name('restaurants.store');
    Route::prefix('/restaurants/{restaurant}')->whereUuid('restaurant')->group(function () {
        Route::get('/', [RestaurantController::class, 'show'])->name('restaurants.show');
        Route::get('/orders', [RestaurantController::class, 'orders'])->name('restaurants.orders');
        Route::get('/payments', [RestaurantController::class, 'payments'])->name('restaurants.payments');
        Route::get('/tables', [TableController::class, 'index'])->name('tables.index');
        Route::get('/tables/new', [TableController::class, 'create'])->name('tables.create');
        Route::post('/tables', [TableController::class, 'store'])->name('tables.store');
        Route::get('/tables/{table}', [TableController::class, 'show'])->whereUuid('table')->name('tables.show');
        Route::get('/tables/{table}/qr.png', [TableController::class, 'qr'])->whereUuid('table')->name('tables.qr');
        Route::post('/tables/{table}/mock-order', [TableController::class, 'mockOrder'])->whereUuid('table')->name('tables.mock-order');
        Route::get('/payments/freedom-pay', [FreedomPayController::class, 'start'])->name('freedom.start');
        Route::post('/payments/freedom-pay/submit', [FreedomPayController::class, 'submit'])->name('freedom.submit');
        Route::get('/payments/freedom-pay/{step}', [FreedomPayController::class, 'show'])->name('freedom.step');
        Route::post('/payments/freedom-pay/{step}', [FreedomPayController::class, 'save'])->name('freedom.save');
    });
    Route::middleware('can:admin')->group(function () {
        Route::get('/admin', [AdminController::class, 'index'])->name('admin');
        Route::get('/admin/freedom-pay/applications', [AdminController::class, 'index'])->name('admin.applications');
        Route::get('/admin/freedom-pay/applications/{application}', [AdminController::class, 'show'])->whereUuid('application')->name('admin.applications.show');
        Route::post('/admin/freedom-pay/applications/{application}/{action}', [AdminController::class, 'update'])->whereUuid('application')->name('admin.applications.update');
    });
});
