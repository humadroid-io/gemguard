module ApplicationHelper
  include Pagy::Method

  # Validates that a URL uses http:// or https:// scheme only.
  # Returns nil for invalid/unsafe URLs (e.g., javascript:, data:, etc.)
  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url.to_s.strip)
    return url if uri.scheme.in?(%w[http https])

    nil
  rescue URI::InvalidURIError
    nil
  end
end
