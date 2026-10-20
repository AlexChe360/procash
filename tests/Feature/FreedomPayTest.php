<?php

namespace Tests\Feature;

use App\Models\FreedomPayApplication;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class FreedomPayTest extends TestCase
{
    use RefreshDatabase;

    private function restaurant(): Restaurant
    {
        $owner = User::factory()->create();
        $this->actingAs($owner);

        return $owner->restaurants()->create(['name' => 'Cafe', 'slug' => 'cafe']);
    }

    private function fillWizard(Restaurant $restaurant): FreedomPayApplication
    {
        $data = [
            'company' => ['organizationType' => 'ТОО', 'companyName' => 'Компания', 'bin' => '123456789012'],
            'director' => ['directorName' => 'Иван Иванов', 'directorIin' => '123456789012', 'directorPhone' => '+7 700 123 45 67', 'directorEmail' => 'DIRECTOR@example.com'],
            'address' => ['legalAddress' => 'ул. Абая, 1', 'city' => 'Алматы', 'postalCode' => '050000'],
            'bank' => ['iban' => 'kz86 125k zt50 0410 0100', 'bankName' => 'Банк', 'bankBic' => 'hsbkkzkx'],
            'restaurant' => ['websiteUrl' => 'https://example.com', 'businessCategory' => 'Кофейня', 'businessDescription' => 'Ресторан и кофейня в центре города Алматы', 'averageCheck' => '2500.50', 'expectedMonthlyTurnover' => '1000000'],
        ];
        $base = '/restaurants/'.$restaurant->id.'/payments/freedom-pay';
        $this->get($base)->assertRedirect($base.'/company');
        foreach ($data as $step => $fields) {
            $this->get($base.'/'.$step)->assertOk();
            $this->post($base.'/'.$step, $fields)->assertSessionHasNoErrors()->assertRedirect();
        }

        return $restaurant->application()->firstOrFail();
    }

    public function test_full_wizard_admin_review_and_approval(): void
    {
        $restaurant = $this->restaurant();
        $app = $this->fillWizard($restaurant);
        $this->assertTrue($app->complete());
        $this->assertSame('KZ86125KZT5004100100', $app->iban);
        $this->assertSame('HSBKKZKX', $app->bank_bic);
        $this->assertSame('director@example.com', $app->director_email);
        $base = '/restaurants/'.$restaurant->id.'/payments/freedom-pay';
        $this->get($base.'/review')->assertOk()->assertSee('Компания');
        $this->post($base.'/submit')->assertRedirect($base.'/status');
        $this->assertSame('READY_FOR_REVIEW', $app->fresh()->status);
        $this->get($base.'/company')->assertRedirect($base.'/status');
        $this->post($base.'/company', ['organization_type' => 'ИП', 'company_name' => 'Changed', 'bin' => '123456789012'])->assertSessionHasErrors('application');
        $admin = User::factory()->create(['role' => 'ADMIN']);
        $this->actingAs($admin)->get('/admin')->assertOk();
        $path = '/admin/freedom-pay/applications/'.$app->id;
        $this->get($path)->assertOk();
        $this->post($path.'/submit')->assertRedirect($path);
        $this->assertSame('UNDER_FREEDOM_REVIEW', $app->fresh()->status);
        $this->assertStringStartsWith('FP-', $app->fresh()->partner_application_id);
        $this->post($path.'/approve')->assertRedirect();
        $this->assertSame('APPROVED', $app->fresh()->status);
        $this->assertStringStartsWith('MERCHANT-', $app->fresh()->merchant_id);
        $this->post($path.'/reject', ['comment' => 'Invalid'])->assertSessionHasErrors('application');
        $this->actingAs($restaurant->owner)->get($base.'/status')->assertOk()->assertSee('Одобрена');
    }

    public function test_returned_application_can_be_corrected_and_resubmitted(): void
    {
        $restaurant = $this->restaurant();
        $app = $this->fillWizard($restaurant);
        $base = '/restaurants/'.$restaurant->id.'/payments/freedom-pay';
        $this->post($base.'/submit');
        $this->actingAs(User::factory()->create(['role' => 'ADMIN']));
        $path = '/admin/freedom-pay/applications/'.$app->id;
        $this->post($path.'/changes', ['comment' => ''])->assertSessionHasErrors('comment');
        $this->post($path.'/changes', ['comment' => 'Исправьте название'])->assertRedirect();
        $this->assertSame('NEEDS_CHANGES', $app->fresh()->status);
        $this->actingAs($restaurant->owner)->get($base.'/company')->assertOk()->assertSee('Исправьте название');
        $this->post($base.'/company', ['organization_type' => 'ТОО', 'company_name' => 'Исправлено', 'bin' => '123456789012'])->assertSessionHasNoErrors()->assertRedirect();
        $this->post($base.'/submit')->assertRedirect();
        $this->assertNull($app->fresh()->review_comment);
    }

    public function test_incomplete_or_invalid_application_is_not_submitted_and_non_admin_cannot_review(): void
    {
        $restaurant = $this->restaurant();
        $base = '/restaurants/'.$restaurant->id.'/payments/freedom-pay';
        $this->get($base);
        $this->post($base.'/submit')->assertSessionHasErrors('application');
        $this->post($base.'/bank', ['iban' => 'bad', 'bank_name' => 'Bank', 'bank_bic' => 'bad'])->assertSessionHasErrors(['iban', 'bank_bic']);
        $app = $restaurant->application()->firstOrFail();
        $this->post('/admin/freedom-pay/applications/'.$app->id.'/approve')->assertForbidden();
        $this->assertSame('DRAFT', $app->fresh()->status);
    }
}
