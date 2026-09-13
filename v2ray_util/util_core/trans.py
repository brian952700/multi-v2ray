#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import gettext
from v2ray_util.resources import resource_filename

lang = 'en'
if os.path.exists('/etc/v2ray_util/util.cfg'):
    from .config import Config
    lang = Config().get_data('lang')
if lang == 'zh':
    trans = gettext.translation('lang', resource_filename('v2ray_util', 'locale_i18n'), languages=['zh_CH'])
else:
    trans = gettext.translation('lang', resource_filename('v2ray_util', 'locale_i18n'), languages=['en_US'])
trans.install()
_ = trans.gettext
