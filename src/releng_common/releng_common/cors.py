# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

from __future__ import absolute_import

from flask_cors import CORS
import os


def init_app(app):
    # Allow specific origins
    origins = os.environ.get('CORS_ORIGINS', '*')

    cors = CORS(origins=origins)
    cors.init_app(app)
    return cors
