<?php

namespace App\Http\Controllers;

use App\Models\Restaurant;
use App\Models\RestaurantTable;
use App\Services\OrderService;
use Endroid\QrCode\QrCode;
use Endroid\QrCode\Writer\PngWriter;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class TableController extends Controller
{
    private function authorizeTable(Restaurant $restaurant, ?RestaurantTable $table = null): void
    {
        Gate::authorize('manage', $restaurant);
        abort_if($table && $table->restaurant_id !== $restaurant->id, 404);
    }

    public function index(Restaurant $restaurant)
    {
        $this->authorizeTable($restaurant);

        return view('tables.index', ['restaurant' => $restaurant, 'tables' => $restaurant->tables()->orderBy('table_number')->get()]);
    }

    public function create(Restaurant $restaurant)
    {
        $this->authorizeTable($restaurant);

        return view('tables.create', compact('restaurant'));
    }

    public function store(Request $request, Restaurant $restaurant)
    {
        $this->authorizeTable($restaurant);
        $data = $request->validate(['table_number' => ['required', 'string', 'max:50'], 'display_name' => ['nullable', 'string', 'max:150']]);
        if ($restaurant->tables()->whereRaw('lower(table_number) = ?', [mb_strtolower($data['table_number'])])->exists()) {
            return back()->withInput()->withErrors(['table_number' => 'Стол с таким номером уже существует.']);
        }
        $table = $restaurant->tables()->create($data);

        return redirect()->route('tables.show', [$restaurant, $table])->with('success', 'Стол создан.');
    }

    public function show(Restaurant $restaurant, RestaurantTable $table)
    {
        $this->authorizeTable($restaurant, $table);

        return view('tables.show', compact('restaurant', 'table'));
    }

    public function qr(Request $request, Restaurant $restaurant, RestaurantTable $table)
    {
        $this->authorizeTable($restaurant, $table);
        $data = $request->validate(['size' => ['sometimes', 'integer', 'between:200,2000']]);
        $qr = new QrCode(data: $table->publicUrl(), size: $data['size'] ?? 640, margin: 16);
        $png = (new PngWriter)->write($qr)->getString();

        return response($png)->header('Content-Type', 'image/png')->header('Content-Disposition', 'attachment; filename="procash-table-'.$table->id.'.png"')->header('Cache-Control', 'private, max-age=3600');
    }

    public function mockOrder(Restaurant $restaurant, RestaurantTable $table, OrderService $orders)
    {
        $this->authorizeTable($restaurant, $table);
        abort_unless(config('procash.mock_orders'), 404);
        $orders->seed($table);

        return redirect()->route('tables.show', [$restaurant, $table])->with('success', 'Тестовый заказ создан.');
    }

    public function publicTable(Request $request, string $slug, string $token)
    {
        $table = RestaurantTable::with('restaurant')->where('qr_token', $token)->where('active', true)->firstOrFail();
        abort_unless(strcasecmp($slug, $table->restaurant->slug) === 0, 404);
        $order = $table->orders()->where('status', 'OPEN')->with('items')->latest('opened_at')->first();

        return view('tables.public', ['table' => $table, 'restaurant' => $table->restaurant, 'order' => $order, 'paymentFailed' => $request->query('payment') === 'failed']);
    }
}
