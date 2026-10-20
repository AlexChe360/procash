<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class NormalizeLegacyInput
{
    public function handle(Request $request, Closure $next)
    {
        foreach (['passwordConfirmation' => 'password_confirmation', 'tableNumber' => 'table_number', 'displayName' => 'display_name', 'orderId' => 'order_id', 'restaurantId' => 'restaurant_id', 'organizationType' => 'organization_type', 'companyName' => 'company_name', 'directorName' => 'director_name', 'directorIin' => 'director_iin', 'directorPhone' => 'director_phone', 'directorEmail' => 'director_email', 'legalAddress' => 'legal_address', 'postalCode' => 'postal_code', 'bankName' => 'bank_name', 'bankBic' => 'bank_bic', 'websiteUrl' => 'website_url', 'businessCategory' => 'business_category', 'businessDescription' => 'business_description', 'averageCheck' => 'average_check', 'expectedMonthlyTurnover' => 'expected_monthly_turnover'] as $legacy => $name) {
            if ($request->exists($legacy) && ! $request->exists($name)) {
                $request->merge([$name => $request->input($legacy)]);
            }
        }

        return $next($request);
    }
}
