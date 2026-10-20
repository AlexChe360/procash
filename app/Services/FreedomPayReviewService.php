<?php

namespace App\Services;

use App\Models\FreedomPayApplication;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class FreedomPayReviewService
{
    public function transition(FreedomPayApplication $application, string $action, ?string $comment): void
    {
        DB::transaction(function () use ($application, $action, $comment) {
            // Same lock order as the owner's wizard prevents stale form overwrites.
            DB::table('restaurants')->where('id', $application->restaurant_id)->lockForUpdate()->first();
            $application = FreedomPayApplication::lockForUpdate()->findOrFail($application->id);
            $allowed = match ($action) {
                'submit', 'return' => ['READY_FOR_REVIEW'],
                'approve', 'reject' => ['UNDER_FREEDOM_REVIEW'],
                'changes' => ['READY_FOR_REVIEW', 'UNDER_FREEDOM_REVIEW'],
                default => [],
            };
            if (! in_array($application->status, $allowed, true)) {
                throw ValidationException::withMessages(['application' => 'Действие недоступно в текущем статусе заявки.']);
            }
            switch ($action) {
                case 'submit':
                    abort_unless(config('procash.mock_payments'), 503, 'Интеграция Freedom Pay не настроена.');
                    if (! $application->complete()) {
                        throw ValidationException::withMessages(['application' => 'Заявка заполнена не полностью.']);
                    }
                    $application->partner_application_id = 'FP-'.strtoupper(substr(str_replace('-', '', Str::uuid()), 0, 12));
                    $application->status = 'UNDER_FREEDOM_REVIEW';
                    break;
                case 'approve':
                    $application->merchant_id ??= 'MERCHANT-'.strtoupper(substr(Str::uuid(), 0, 8));
                    $application->status = 'APPROVED';
                    $application->review_comment = null;
                    break;
                case 'reject':
                    $application->status = 'REJECTED';
                    $application->review_comment = $comment;
                    break;
                default:
                    $application->status = 'NEEDS_CHANGES';
                    $application->current_step = 'COMPANY';
                    $application->review_comment = $comment;
            }
            $application->save();
        });
    }
}
