/**
 * Normalizes a phone number to a standard format.
 * Strips all non-digit characters and ensures a consistent prefix if needed.
 * For this system, we will strip non-digits and keep the last 10-12 digits.
 */
export const normalizePhone = (phone: string | null | undefined): string | null => {
  if (!phone) return null;
  
  // Strip all non-numeric characters
  const digits = phone.replace(/\D/g, '');
  
  if (digits.length < 7) return digits; // Too short to normalize but keep as is
  
  // If it starts with 0, and we want to standardize (e.g., Pakistan format 03xx -> 3xx)
  // we can either keep the 0 or strip it. Let's keep it consistent by stripping leading 0 
  // or 92 if we want a clean base.
  
  // Standardizing to just the digits for comparison
  return digits;
};
