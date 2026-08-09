UPDATE freedom_pay_applications
SET status = 'READY_FOR_REVIEW'
WHERE status = 'READY_TO_SUBMIT';

UPDATE freedom_pay_applications
SET status = 'SUBMITTED_TO_FREEDOM'
WHERE status = 'SUBMITTED';

UPDATE freedom_pay_applications
SET status = 'UNDER_FREEDOM_REVIEW'
WHERE status = 'UNDER_REVIEW';