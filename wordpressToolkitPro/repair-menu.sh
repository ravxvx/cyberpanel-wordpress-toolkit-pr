#!/bin/sh
# Adds the "WP Toolkit Pro" sidebar link to CyberPanel if it is missing.
# Safe to run any time (also after a CyberPanel upgrade, which overwrites the template):
#   sh /usr/local/CyberCP/wordpressToolkitPro/repair-menu.sh
IDX="${1:-/usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html}"
[ -f "$IDX" ] || { echo "Template not found: $IDX"; exit 1; }
if grep -q "url 'wordpressToolkitPro'" "$IDX"; then
  echo "Sidebar link already present."; exit 0
fi
sed -i "/url 'ListWPSites' %}\" class=\"menu-item\"/i <a href=\"{% url 'wordpressToolkitPro' %}\" class=\"menu-item\">\n            <div class=\"icon-wrapper\"><i class=\"fas fa-download\"></i></div>\n            <span>WP Toolkit Pro</span>\n        </a>" "$IDX"
if grep -q "url 'wordpressToolkitPro'" "$IDX"; then
  echo "Sidebar link added."
else
  # fallback: put it right after the Websites item
  sed -i "/url 'listWebsites' %}\" class=\"menu-item\"/i <a href=\"{% url 'wordpressToolkitPro' %}\" class=\"menu-item\">\n            <div class=\"icon-wrapper\"><i class=\"fas fa-download\"></i></div>\n            <span>WP Toolkit Pro</span>\n        </a>" "$IDX"
  grep -q "url 'wordpressToolkitPro'" "$IDX" && echo "Sidebar link added (fallback)." || { echo "WARNING: could not add link; open /wordpressToolkitPro/ directly."; exit 1; }
fi
