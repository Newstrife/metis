module AvatarHelper
  # Renders an avatar for `user` at `size` pixels. Resolution order:
  # uploaded Active Storage attachment (2x variant for HiDPI) →
  # OAuth-cached URL → initials placeholder. External URLs get
  # `referrerpolicy=no-referrer` so the provider can't see which
  # page is requesting the image.
  def avatar_for(user, size: 32, css: "avatar")
    if user.avatar.attached?
      target = size * 2
      image_tag(user.avatar.variant(resize_to_fill: [ target, target ]),
                width: size, height: size, class: css, alt: "", loading: "lazy")
    elsif user.avatar_url.present?
      image_tag(user.avatar_url,
                width: size, height: size, class: css, alt: "",
                loading: "lazy", referrerpolicy: "no-referrer")
    else
      content_tag(:div, user.initials, class: css, "aria-hidden": "true")
    end
  end
end
