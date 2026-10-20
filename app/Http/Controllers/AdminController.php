<?php

namespace App\Http\Controllers;

use App\Models\FreedomPayApplication;
use App\Services\FreedomPayReviewService;
use Illuminate\Http\Request;

class AdminController extends Controller
{
    public function index()
    {
        return view('admin.index', ['applications' => FreedomPayApplication::with('restaurant.owner')->latest()->paginate(30), 'counts' => FreedomPayApplication::selectRaw('status, count(*) as total')->groupBy('status')->pluck('total', 'status')]);
    }

    public function show(FreedomPayApplication $application)
    {
        return view('admin.show', ['application' => $application->load('restaurant.owner')]);
    }

    public function update(Request $request, FreedomPayApplication $application, string $action, FreedomPayReviewService $reviews)
    {
        abort_unless(in_array($action, ['submit', 'return', 'approve', 'reject', 'changes'], true), 404);
        $data = $request->validate(['comment' => [in_array($action, ['reject', 'changes'], true) ? 'required' : 'nullable', 'string', 'max:5000']]);
        $reviews->transition($application, $action, $data['comment'] ?? null);

        return redirect()->route('admin.applications.show', $application)->with('success', 'Статус заявки обновлён.');
    }
}
