const { setGlobalOptions } = require('firebase-functions');
const { onRequest } = require('firebase-functions/v2/https');
const ffmpegPath = require('ffmpeg-static');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

initializeApp();


setGlobalOptions({
    maxInstances: 2,
});

exports.createECardVideo = onRequest(
    {
        timeoutSeconds: 120,
        memory: '1GiB',
        cors: true,
    },
    async (req, res) => {
        const authorization = req.headers.authorization || '';

        if (!authorization.startsWith('Bearer ')) {
            res.status(401).json({
                error: 'Se requiere autenticación.',
            });
            return;
        }

        try {
            const idToken = authorization.substring(7);
            await getAuth().verifyIdToken(idToken);
        } catch (_) {
            res.status(401).json({
                error: 'La sesión no es válida.',
            });
            return;
        }

        if (req.method !== 'POST') {
            res.status(405).json({
                error: 'Solo se permiten solicitudes POST.',
            });
            return;
        }

        try {
            const {
                envelopeBase64,
                cardBase64,
            } = req.body || {};

            if (!envelopeBase64 || !cardBase64) {
                res.status(400).json({
                    error: 'Faltan las imágenes del sobre o de la tarjeta.',
                });
                return;
            }

            const tempDirectory = fs.mkdtempSync(
                path.join(os.tmpdir(), 'ecard-'),
            );

            const envelopePath = path.join(
                tempDirectory,
                'envelope.png',
            );

            const cardPath = path.join(
                tempDirectory,
                'card.png',
            );

            const outputPath = path.join(
                tempDirectory,
                'ecard.mp4',
            );

            fs.writeFileSync(
                envelopePath,
                Buffer.from(
                    envelopeBase64.replace(
                        /^data:image\/png;base64,/,
                        '',
                    ),
                    'base64',
                ),
            );

            fs.writeFileSync(
                cardPath,
                Buffer.from(
                    cardBase64.replace(
                        /^data:image\/png;base64,/,
                        '',
                    ),
                    'base64',
                ),
            );

            await runFfmpeg([
                '-y',

                '-loop',
                '1',
                '-i',
                envelopePath,

                '-loop',
                '1',
                '-i',
                cardPath,

                '-filter_complex',
                [
                    '[0:v]',
                    'scale=1200:800:force_original_aspect_ratio=decrease,',
                    'pad=1200:800:(ow-iw)/2:(oh-ih)/2,',
                    'fps=30,trim=duration=2,setpts=PTS-STARTPTS[envelope];',

                    '[1:v]',
                    'scale=1200:800:force_original_aspect_ratio=decrease,',
                    'pad=1200:800:(ow-iw)/2:(oh-ih)/2,',
                    'fps=30,trim=duration=8,setpts=PTS-STARTPTS[card];',

                    '[envelope][card]',
                    'xfade=transition=fade:duration=0.8:offset=1.2,',
                    'format=yuv420p[video]',
                ].join(''),

                '-map',
                '[video]',

                '-r',
                '30',
                '-t',
                '10',

                '-c:v',
                'libx264',
                '-pix_fmt',
                'yuv420p',

                '-movflags',
                'faststart',

                outputPath,
            ]);

            const videoBuffer = fs.readFileSync(outputPath);

            res.set('Content-Type', 'video/mp4');
            res.set(
                'Content-Disposition',
                'attachment; filename="ecard_el_cielo.mp4"',
            );

            res.status(200).send(videoBuffer);

            fs.rmSync(tempDirectory, {
                recursive: true,
                force: true,
            });
        } catch (error) {
            console.error('Error al crear el video:', error);

            res.status(500).json({
                error: 'No se pudo crear el video de la E-card.',
            });
        }
    },
);

function runFfmpeg(argumentsList) {
    return new Promise((resolve, reject) => {
        const process = spawn(ffmpegPath, argumentsList);

        let errorOutput = '';

        process.stderr.on('data', (data) => {
            errorOutput += data.toString();
        });

        process.on('error', reject);

        process.on('close', (code) => {
            if (code === 0) {
                resolve();
            } else {
                reject(
                    new Error(
                        `FFmpeg terminó con código \({code}: \){errorOutput}`,
                    ),
                );
            }
        });
    });
}

