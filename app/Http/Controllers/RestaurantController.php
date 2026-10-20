<?php

namespace App\Http\Controllers;

use App\Models\Restaurant;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;

class RestaurantController extends Controller
{
    public function index(Request $request)
    {
        return view('restaurants.index', ['restaurants' => $request->user()->restaurants()->withCount('tables')->latest()->get()]);
    }

    public function create()
    {
        return view('restaurants.create');
    }

    public function store(Request $request)
    {
        $request->merge(['slug' => mb_strtolower(trim($request->string('slug')))]);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:150'],
            'slug' => ['required', 'string', 'max:150', 'regex:/^[a-z0-9]+(?:-[a-z0-9]+)*$/', Rule::unique('restaurants', 'slug')],
            'description' => ['nullable', 'string', 'max:1000'],
            'phone' => ['nullable', 'string', 'max:30'],
            'city' => ['nullable', 'string', 'max:100'],
        ]);
        if (Restaurant::whereRaw('lower(slug) = ?', [$data['slug']])->exists()) {
            return back()->withInput()->withErrors(['slug' => 'Ресторан с таким адресом уже существует.']);
        }
        $restaurant = $request->user()->restaurants()->create($data);

        return redirect()->route('restaurants.show', $restaurant)->with('success', 'Ресторан создан.');
    }

    public function show(Restaurant $restaurant)
    {
        Gate::authorize('manage', $restaurant);

        return view('restaurants.show', ['restaurant' => $restaurant->loadCount('tables')->load('application')]);
    }

    public function orders(Restaurant $restaurant)
    {
        Gate::authorize('manage', $restaurant);

        return view('orders.index', ['restaurant' => $restaurant, 'orders' => $restaurant->orders()->with('table', 'items')->latest('opened_at')->paginate(30)]);
    }

    public function payments(Restaurant $restaurant)
    {
        Gate::authorize('manage', $restaurant);

        return view('payments.index', ['restaurant' => $restaurant, 'payments' => $restaurant->payments()->with('order')->latest()->paginate(30)]);
    }
}
