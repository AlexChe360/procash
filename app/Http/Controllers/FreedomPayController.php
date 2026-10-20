<?php

namespace App\Http\Controllers;

use App\Models\FreedomPayApplication;
use App\Models\Restaurant;
use App\Support\FreedomPaySteps;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\ValidationException;

class FreedomPayController extends Controller
{
    private function application(Restaurant $restaurant): FreedomPayApplication
    {
        Gate::authorize('manage', $restaurant);

        return $restaurant->application()->firstOrCreate();
    }

    public function start(Restaurant $restaurant)
    {
        $application = $this->application($restaurant);
        $step = $application->editable() ? strtolower($application->current_step) : 'status';
        if ($step === 'submit') {
            $step = 'review';
        }

        return redirect()->route('freedom.step', [$restaurant, $step]);
    }

    public function show(Restaurant $restaurant, string $step)
    {
        $application = $this->application($restaurant);
        abort_unless(isset(FreedomPaySteps::STEPS[$step]) || in_array($step, ['status', 'success'], true), 404);
        if (! $application->editable() && isset(FreedomPaySteps::STEPS[$step])) {
            return redirect()->route('freedom.step', [$restaurant, 'status']);
        }

        return view('freedom.show', compact('restaurant', 'application', 'step'));
    }

    public function save(Request $request, Restaurant $restaurant, string $step)
    {
        Gate::authorize('manage', $restaurant);
        abort_unless(isset(FreedomPaySteps::STEPS[$step]) && $step !== 'review', 404);
        if ($step === 'bank') {
            foreach (['iban', 'bank_bic'] as $field) {
                $request->merge([$field => strtoupper(preg_replace('/\s+/', '', $request->string($field)))]);
            }
        }
        if ($step === 'director') {
            $request->merge(['director_email' => mb_strtolower($request->string('director_email'))]);
        }
        if ($step === 'company') {
            $request->merge(['organization_type' => mb_strtoupper($request->string('organization_type'))]);
        }
        $data = $request->validate(FreedomPaySteps::rules($step), [], FreedomPaySteps::fields($step));
        DB::transaction(function () use ($restaurant, $data, $step) {
            $restaurant = Restaurant::lockForUpdate()->findOrFail($restaurant->id);
            $application = $restaurant->application()->firstOrCreate();
            if (! $application->editable()) {
                throw ValidationException::withMessages(['application' => 'Отправленную заявку нельзя редактировать.']);
            }
            $steps = array_keys(FreedomPaySteps::STEPS);
            $application->fill($data);
            $application->current_step = strtoupper($steps[array_search($step, $steps, true) + 1]);
            if ($step === 'restaurant') {
                $application->status = 'DRAFT';
            }
            $application->save();
        });
        $steps = array_keys(FreedomPaySteps::STEPS);

        return redirect()->route('freedom.step', [$restaurant, $steps[array_search($step, $steps, true) + 1]]);
    }

    public function submit(Restaurant $restaurant)
    {
        Gate::authorize('manage', $restaurant);
        DB::transaction(function () use ($restaurant) {
            Restaurant::lockForUpdate()->findOrFail($restaurant->id);
            $application = $restaurant->application()->lockForUpdate()->firstOrFail();
            if (! $application->editable() || ! $application->complete()) {
                throw ValidationException::withMessages(['application' => 'Заполните все шаги заявки перед отправкой.']);
            }
            $application->status = 'READY_FOR_REVIEW';
            $application->current_step = 'SUBMIT';
            $application->review_comment = null;
            $application->save();
        });

        return redirect()->route('freedom.step', [$restaurant, 'status'])->with('success', 'Заявка отправлена на проверку.');
    }
}
