%{

/*
 *  Advanced Linux Sound Architecture Control Program
 *  Copyright (c) 1998 by Perex, APS, University of South Bohemia
 *
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#include "alsactl.h"
#include <stdarg.h>

	/* insgus_lexer.c */

int yylex( void );

extern char cfgfile[];
extern int linecount;
extern FILE *yyin;

	/* local functions */

static void yyerror(char *, ...);

static void select_soundcard(char *name);
static void select_mixer(char *name);
static void select_pcm(char *name);
static void select_rawmidi(char *name);

static void select_mixer_channel(char *name);
static void select_mixer_direction(int direction);
static void select_mixer_voice(int voice);
static void set_mixer_volume(int volume);
static void set_mixer_flags(int flags);
static void select_mixer_channel_end(void);

#define SWITCH_CONTROL		0
#define SWITCH_MIXER		1
#define SWITCH_PCM		2
#define SWITCH_RAWMIDI		3

static void select_control_switch(char *name);
static void select_mixer_switch(char *name);
static void select_pcm_playback_switch(char *name);
static void select_pcm_record_switch(char *name);
static void select_rawmidi_output_switch(char *name);
static void select_rawmidi_input_switch(char *name);

static void set_switch_boolean(int val);
static void set_switch_integer(int val);
static void set_switch_iec958ocs_begin(int end);
static void set_switch_iec958ocs(int idx, unsigned short val, unsigned short mask);

	/* local variables */

static struct soundcard *Xsoundcard = NULL;
static struct mixer *Xmixer = NULL;
static struct pcm *Xpcm = NULL;
static struct rawmidi *Xrawmidi = NULL;
static struct mixer_channel *Xchannel = NULL;
static int Xswitchtype = SWITCH_CONTROL;
static int *Xswitchchange = NULL;
static snd_switch_t *Xswitch = NULL;
static unsigned int Xswitchiec958ocs = 0;
static unsigned short Xswitchiec958ocs1[16];

%}

%start lines

%union {
    int b_value;
    int i_value;
    char *s_value;
    unsigned char *a_value;
  };

%token <b_value> L_TRUE L_FALSE
%token <i_value> L_INTEGER
%token <s_value> L_STRING
%token <a_value> L_BYTEARRAY

	/* types */
%token L_INTEGER L_STRING
	/* boolean */
%token L_FALSE L_TRUE
	/* misc */
%token L_DOUBLE1
	/* other keywords */
%token L_SOUNDCARD L_MIXER L_CHANNEL L_STEREO L_MONO L_SWITCH L_RAWDATA
%token L_CONTROL L_PCM L_RAWMIDI L_PLAYBACK L_RECORD L_OUTPUT L_INPUT
%token L_IEC958OCS L_3D L_RESET L_USER L_VALID L_DATA L_PROTECT L_PRE2
%token L_FSUNLOCK L_TYPE L_GSTATUS L_ENABLE L_DISABLE L_MUTE L_SWAP

%type <b_value> boolean
%type <i_value> integer
%type <s_value> string
%type <a_value> bytearray

%%

lines	: line
	| lines line
	;

line	: L_SOUNDCARD '(' string { select_soundcard( $3 ); } L_DOUBLE1 soundcards { select_soundcard( NULL ); } '}'
	| error			{ yyerror( "unknown keyword in top level" ); }
	;

soundcards : soundcard
	| soundcards soundcard
	;

soundcard : L_CONTROL '{' controls '}'
	| L_MIXER '(' string { select_mixer( $3 ); } L_DOUBLE1 mixers { select_mixer( NULL ); } '}'
	| L_PCM '(' string { select_pcm( $3 ); } L_DOUBLE1 pcms { select_pcm( NULL ); } '}'
	| L_RAWMIDI '(' string { select_rawmidi( $3 ); } L_DOUBLE1 rawmidis { select_rawmidi( NULL ); } '}'
	| error			{ yyerror( "unknown keyword in soundcard{} level" ); }
	;

controls : control
	| controls control
	;

control : L_SWITCH '(' string { select_control_switch( $3 ); } ',' switches ')' { select_control_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in control{} level" ); }
	;

mixers	: mixer
	| mixers mixer
	;

mixer	: L_CHANNEL '(' string	{ select_mixer_channel( $3 ); } 
	  ',' settings ')' 	{ select_mixer_channel_end(); 
	  			  select_mixer_channel( NULL ); }
	| L_SWITCH '(' string	{ select_mixer_switch( $3 ); }
	  ',' switches ')'	{ select_mixer_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in mixer level" ); }
	;


settings: setting
	| settings ',' setting
	;

setting	: L_OUTPUT		{ select_mixer_direction(OUTPUT); }
	  dsetting
	| L_INPUT		{ select_mixer_direction(INPUT); }
	  dsetting
	| error			{ yyerror( "unknown keyword in mixer channel level" ); }
	;

dsetting: L_STEREO '('		{ select_mixer_voice(LEFT); }
	vsettings ','		{ select_mixer_voice(RIGHT); }
	vsettings ')'
	| L_MONO '('		{ select_mixer_voice(LEFT|RIGHT); }
	  vsettings ')'
	| error			{ yyerror( "unknown keyword in mixer direction level" ); }
	;

vsettings: vsetting
	| vsettings vsetting
	;

vsetting: L_INTEGER		{ set_mixer_volume($1); }
	| L_MUTE		{ set_mixer_flags(SND_MIXER_DFLG_MUTE); }
	| L_SWAP		{ set_mixer_flags(SND_MIXER_DFLG_SWAP); }
	| error			{ yyerror( "unknown keyword in mixer voice level" ); }
	;

pcms	: pcm
	| pcms pcm
	;

pcm	: L_PLAYBACK '{' playbacks '}'
	| L_RECORD '{' records '}'
	| error			{ yyerror( "unknown keyword in pcm{} section" ); }
	;

playbacks : playback
	| playbacks playback
	;

playback : L_SWITCH '(' string { select_pcm_playback_switch( $3 ); } ',' switches ')' { select_pcm_playback_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in playback{} section" ); }
	;

records : record
	| records record
	;

record	: L_SWITCH '(' string { select_pcm_record_switch( $3 ); } ',' switches ')' { select_pcm_record_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in record{} section" ); }
	;

rawmidis : rawmidi
	| rawmidis rawmidi
	;

rawmidi	: L_INPUT '{' inputs '}'
	| L_OUTPUT '{' outputs '}'
	;

inputs	: input
	| inputs input
	;

input	: L_SWITCH '(' string { select_rawmidi_input_switch( $3 ); } ',' switches ')' { select_rawmidi_input_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in input{} section" ); }
	;

outputs	: output
	| outputs output
	;

output	: L_SWITCH '(' string { select_rawmidi_output_switch( $3 ); } ',' switches ')' { select_rawmidi_output_switch( NULL ); }
	| error			{ yyerror( "unknown keyword in output{} section" ); }
	;

switches : switch
	| switches switch
	;

switch	: L_TRUE		{ set_switch_boolean( 1 ); }
	| L_FALSE		{ set_switch_boolean( 0 ); }
	| L_INTEGER		{ set_switch_integer( $1 ); }
	| L_IEC958OCS '(' { set_switch_iec958ocs_begin( 0 ); } iec958ocs { set_switch_iec958ocs_begin( 1 ); } ')'
	| error			{ yyerror( "unknown keyword in switch() data parameter" ); }
	;

iec958ocs : iec958ocs1
	| iec958ocs iec958ocs1
	;

iec958ocs1 : L_ENABLE		{ set_switch_iec958ocs( 0, 1, 0 ); }
	| L_DISABLE		{ set_switch_iec958ocs( 0, 0, 0 ); }
	| L_3D			{ set_switch_iec958ocs( 4, 0x2000, ~0x2000 ); }
	| L_RESET		{ set_switch_iec958ocs( 4, 0x0040, ~0x0040 ); }
	| L_USER		{ set_switch_iec958ocs( 4, 0x0020, ~0x0020 ); }
	| L_VALID		{ set_switch_iec958ocs( 4, 0x0010, ~0x0010 ); }
	| L_DATA		{ set_switch_iec958ocs( 5, 0x0002, ~0x0002 ); }
	| L_PROTECT		{ set_switch_iec958ocs( 5, 0, ~0x0004 ); }
	| L_PRE2		{ set_switch_iec958ocs( 5, 0x0008, ~0x0018 ); }
	| L_FSUNLOCK		{ set_switch_iec958ocs( 5, 0x0020, ~0x0020 ); }
	| L_TYPE '(' integer ')' { set_switch_iec958ocs( 5, ($3 & 0x7f) << 6, ~(0x7f<<6) ); }
	| L_GSTATUS		{ set_switch_iec958ocs( 5, 0x2000, ~0x2000 ); }
	| error			{ yyerror( "unknown keyword in iec958ocs1() arguments" ); }
	;

boolean	: L_TRUE		{ $$ = 1; }
	| L_FALSE		{ $$ = 0; }
	| error			{ yyerror( "unknown boolean value" ); }
	;

integer	: L_INTEGER		{ $$ = $1; }
	| error			{ yyerror( "unknown integer value" ); }
	;

string	: L_STRING		{ $$ = $1; }
	| error			{ yyerror( "unknown string value" ); }
	;

bytearray : L_BYTEARRAY		{ $$ = $1; }
	| error			{ yyerror( "unknown byte array value" ); }
	;

%%

static void yyerror(char *string,...)
{
	char errstr[1024];

	va_list vars;
	va_start(vars, string);
	vsprintf(errstr, string, vars);
	va_end(vars);
	error("Error in configuration file '%s' (line %i): %s", cfgfile, linecount + 1, errstr);

	exit(1);
}

static void select_soundcard(char *name)
{
	struct soundcard *soundcard;

	if (!name) {
		Xsoundcard = NULL;
		return;
	}
	for (soundcard = soundcards; soundcard; soundcard = soundcard->next)
		if (!strcmp(soundcard->control.hwinfo.id, name)) {
			Xsoundcard = soundcard;
			free(name);
			return;
		}
	yyerror("Cannot find soundcard '%s'...", name);
	free(name);
}

static void select_mixer(char *name)
{
	struct mixer *mixer;

	if (!name) {
		Xmixer = NULL;
		return;
	}
	for (mixer = Xsoundcard->mixers; mixer; mixer = mixer->next)
		if (!strcmp(mixer->info.name, name)) {
			Xmixer = mixer;
			free(name);
			return;
		}
	yyerror("Cannot find mixer '%s' for soundcard '%s'...", name, Xsoundcard->control.hwinfo.id);
	free(name);
}

static void select_pcm(char *name)
{
	struct pcm *pcm;

	if (!name) {
		Xpcm = NULL;
		return;
	}
	for (pcm = Xsoundcard->pcms; pcm; pcm = pcm->next)
		if (!strcmp(pcm->info.name, name)) {
			Xpcm = pcm;
			free(name);
			return;
		}
	yyerror("Cannot find pcm device '%s' for soundcard '%s'...", name, Xsoundcard->control.hwinfo.id);
	free(name);
}

static void select_rawmidi(char *name)
{
	struct rawmidi *rawmidi;

	if (!name) {
		Xrawmidi = NULL;
		return;
	}
	for (rawmidi = Xsoundcard->rawmidis; rawmidi; rawmidi = rawmidi->next)
		if (!strcmp(rawmidi->info.name, name)) {
			Xrawmidi = rawmidi;
			free(name);
			return;
		}
	yyerror("Cannot find rawmidi device '%s' for soundcard '%s'...", name, Xsoundcard->control.hwinfo.id);
	free(name);
}

static void select_mixer_channel(char *name)
{
	struct mixer_channel *channel;

	if (!name) {
		Xchannel = NULL;
		return;
	}
	for (channel = Xmixer->channels; channel; channel = channel->next)
		if (!strcmp(channel->info.name, name)) {
			Xchannel = channel;
			Xchannel->ddata[OUTPUT].flags = 0;
			Xchannel->ddata[INPUT].flags = 0;
			free(name);
			return;
		}
	yyerror("Cannot find mixer channel '%s'...", name);
	free(name);
}

static void select_mixer_direction(int direction)
{
	Xchannel->direction = direction;
}

static void select_mixer_voice(int voice)
{
	Xchannel->voice = voice;
}

static void set_mixer_volume(int volume)
{
	snd_mixer_channel_direction_info_t *i = &Xchannel->dinfo[Xchannel->direction];
	snd_mixer_channel_direction_t *d = &Xchannel->ddata[Xchannel->direction];
	if (Xchannel->voice & LEFT) {
		if (i->min > volume || i->max < volume)
			yyerror("Value out of range (%i-%i)...", i->min, i->max);
		d->left = volume;
	}
	if (Xchannel->voice & RIGHT) {
		if (i->min > volume || i->max < volume)
			yyerror("Value out of range (%i-%i)...", i->min, i->max);
		d->right = volume;
	}
}

static void set_mixer_flags(int flags)
{
	snd_mixer_channel_direction_t *d = &Xchannel->ddata[Xchannel->direction];
	if (Xchannel->voice & LEFT) {
		if (flags & SND_MIXER_DFLG_MUTE)
			d->flags |= SND_MIXER_DFLG_MUTE_LEFT;
		if (flags & SND_MIXER_DFLG_SWAP)
			d->flags |= SND_MIXER_DFLG_LTOR;
	}
	if (Xchannel->voice & RIGHT) {
		if (flags & SND_MIXER_DFLG_MUTE)
			d->flags |= SND_MIXER_DFLG_MUTE_RIGHT;
		if (flags & SND_MIXER_DFLG_SWAP)
			d->flags |= SND_MIXER_DFLG_RTOL;
	}
}

static void select_mixer_channel_end(void)
{
}

static void find_switch(int xtype, struct ctl_switch *first, char *name, char *err)
{
	struct ctl_switch *sw;

	if (!name) {
		Xswitch = NULL;
		Xswitchchange = NULL;
		return;
	}
	for (sw = first; sw; sw = sw->next) {
		if (!strcmp(sw -> s.name, name)) {
			Xswitchtype = xtype;
			Xswitchchange = &sw->change;
			Xswitch = &sw->s;
			free(name);
			return;
		}
	}
	yyerror("Cannot find %s switch '%s'...", err, name);
	free(name);
}

static void select_control_switch(char *name)
{
	find_switch(SWITCH_CONTROL, Xsoundcard->control.switches, name, "control");
}

static void select_mixer_switch(char *name)
{
	find_switch(SWITCH_MIXER, Xmixer->switches, name, "mixer");
}

static void select_pcm_playback_switch(char *name)
{
	find_switch(SWITCH_PCM, Xpcm->pswitches, name, "pcm playback");
}

static void select_pcm_record_switch(char *name)
{
	find_switch(SWITCH_PCM, Xpcm->rswitches, name, "pcm record");
}

static void select_rawmidi_output_switch(char *name)
{
	find_switch(SWITCH_RAWMIDI, Xrawmidi->oswitches, name, "rawmidi output");
}

static void select_rawmidi_input_switch(char *name)
{
	find_switch(SWITCH_RAWMIDI, Xrawmidi->iswitches, name, "rawmidi input");
}

static void set_switch_boolean(int val)
{
	snd_switch_t *sw = Xswitch;
	unsigned int xx;

	if (sw->type != SND_SW_TYPE_BOOLEAN)
		yyerror("Switch '%s' isn't boolean type...", sw->name);
	xx = val ? 1 : 0;
	if (sw->value.enable != xx)
		*Xswitchchange = 1;
	sw->value.enable = xx;
#if 0
	printf("name = '%s', sw->value.enable = %i\n", sw->name, xx);
#endif
}

static void set_switch_integer(int val)
{
	snd_switch_t *sw = Xswitch;
	unsigned int xx;

	if (sw->type != SND_SW_TYPE_BYTE &&
	    sw->type != SND_SW_TYPE_WORD &&
	    sw->type != SND_SW_TYPE_DWORD)
		yyerror("Switch '%s' isn't integer type...", sw->name);
	if (val < sw->low || val > sw->high)
		yyerror("Value for switch '%s' out of range (%i-%i)...\n", sw->name, sw->low, sw->high);
	xx = val;
	if (memcmp(&sw->value, &xx, sizeof(xx)))
		*Xswitchchange = 1;
	memcpy(&sw->value, &xx, sizeof(xx));
}

static void set_switch_iec958ocs_begin(int end)
{
	snd_switch_t *sw = Xswitch;

	if (end) {
		if (Xswitchiec958ocs != sw->value.enable) {
			sw->value.enable = Xswitchiec958ocs;
			*Xswitchchange = 1;
		}
		if (Xswitchiec958ocs1[4] != sw->value.data16[4]) {
			sw->value.data16[4] = Xswitchiec958ocs1[4];
			*Xswitchchange = 1;
		}
		if (Xswitchiec958ocs1[5] != sw->value.data16[5]) {
			sw->value.data16[5] = Xswitchiec958ocs1[5];
			*Xswitchchange = 1;
		}
#if 0
		printf("IEC958: enable = %i, ocs1[4] = 0x%x, ocs1[5] = 0x%x\n",
		       sw->value.enable,
		       sw->value.data16[4],
		       sw->value.data16[5]);
#endif
		return;
	}
	if (Xswitchtype != SWITCH_MIXER || sw->type != SND_SW_TYPE_BOOLEAN ||
	    strcmp(sw->name, SND_MIXER_SW_IEC958OUT))
		yyerror("Switch '%s' cannot store IEC958 information for Cirrus Logic chips...", sw->name);
	if (sw->value.data32[1] != (('C' << 8) | 'S'))
		yyerror("Switch '%s' doesn't have Cirrus Logic signature!!!", sw->name);
	Xswitchiec958ocs = 0;
	Xswitchiec958ocs1[4] = 0x0000;
	Xswitchiec958ocs1[5] = 0x0004;	/* copy permitted */
}

static void set_switch_iec958ocs(int idx, unsigned short val, unsigned short mask)
{
	if (idx == 0) {
		Xswitchiec958ocs = val ? 1 : 0;
		return;
	}
	Xswitchiec958ocs1[idx] &= mask;
	Xswitchiec958ocs1[idx] |= val;
}
