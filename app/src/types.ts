export interface Note {
    midi: number;
    ticks: number;
    durationTicks: number;
    velocity: number;
}

export interface Track {
    name: string;
    notes: Note[];
}

export interface Song {
    header: {
        tempo: number;
        ppq: number;
        timeSignature: [number, number];
    };
    tracks: Track[];
}
