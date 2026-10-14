// RevenueCat customers, server side. The app runs RevenueCat in observer mode
// for subscription analytics, keyed to the Supabase user id, so deleting an
// account must delete those customers too. Optional: without a secret key this
// logs a warning and skips (deletion still goes ahead).
// Secrets: REVENUECAT_SECRET_KEY, plus REVENUECAT_PROJECT_ID for a v2 key
// (preferred: limit it to customer_information:customers:read_write). A key
// without a project id is used with the v1 API. v1 and v2 keys are not
// interchangeable.

const API = "https://api.revenuecat.com";

// The app sends `UUID.uuidString`, which is upper case, while Supabase ids are
// lower case. Customer ids are case sensitive, so both spellings are deleted.
function spellings(userID: string): string[] {
  return [...new Set([userID.toUpperCase(), userID.toLowerCase()])];
}

async function deleteCustomer(customerID: string, key: string, projectID: string | undefined): Promise<boolean> {
  const id = encodeURIComponent(customerID);
  const url = projectID
    ? `${API}/v2/projects/${encodeURIComponent(projectID)}/customers/${id}`
    : `${API}/v1/subscribers/${id}`;
  const response = await fetch(url, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${key}` },
    signal: AbortSignal.timeout(8000),
  });
  await response.body?.cancel();
  // 404: never a customer (she never bought), or already deleted.
  return response.ok || response.status === 404;
}

/// Deletes the RevenueCat customers for these Supabase user ids. RevenueCat
/// queues the deletion. Never throws: a failure is logged, not fatal.
export async function deleteRevenueCatCustomers(userIDs: string[]): Promise<void> {
  const key = Deno.env.get("REVENUECAT_SECRET_KEY");
  if (!key) {
    console.warn("REVENUECAT_SECRET_KEY is not set; skipping RevenueCat customer deletion");
    return;
  }
  const projectID = Deno.env.get("REVENUECAT_PROJECT_ID") || undefined;
  for (const customerID of userIDs.flatMap(spellings)) {
    try {
      if (!(await deleteCustomer(customerID, key, projectID))) {
        console.warn("couldn't delete RevenueCat customer", customerID);
      }
    } catch {
      console.warn("couldn't reach RevenueCat to delete customer", customerID);
    }
  }
}
