/* SAS program that implements Wordle                                 */
/* Uses "official" Wordle game word list & permitted guess words      */
/* Implemented by Chris Hemedinger, SAS                               */
/* Credit to cfreshman on GitHub for the word lists                   */
/* And of course to Josh Wardle for the fun game concept              */

/* Get word list */
filename words temp;
filename words_ok temp;

/* "Official" word lists from NYT, via cfreshman GitHub sharing */
proc http
	url="https://gist.githubusercontent.com/cfreshman/a7b776506c73284511034e63af1017ee/raw/845966807347a7b857d53294525263408be967ce/wordle-nyt-answers-alphabetical.txt"
	out=words;
run;

proc http
	url="https://gist.githubusercontent.com/cfreshman/40608e78e83eb4e1d60b285eb7e9732f/raw/2f51b4f2bb96c02e1dee37808b2eed4ef23a3150/wordle-nyt-allowed-guesses.txt"
	out=words_ok;
run;

data words;
	infile words;
	length word $ 5;
	input word;
run;

%let wordcount = &sysnobs.;

/* valid guesses that aren't necessarily in word list
  via cfreshman GitHub sharing
*/
data allowed_words;
	infile words_ok;
	length word $ 5;
	input word;
run;

/* allowed guesses plus game words => universe of allowed guesses */
data allowed_words;
	set allowed_words words;
run;

/*
use this to seed a new game. Will create a macro variable with the word - don't peek!
supply 'seed' value to set the word explicitly, good for testing
*/
%macro startGame(seed);
  %global gamepick;

  %if %length(&seed) = 5 %then
    %let gamepick=&seed;
  %else
    %do;
      %let pick = %sysfunc(rand(Integer,1,&wordcount.));
      data _null_;
        set words (obs=&pick. firstobs=&pick.);
        call symput('gamepick',word);
      run;
    %end;
  data status;
    array check{5}  $ 8 checked1-checked5;
    length status $ 5;
    stop;
  run;
%mend;

/* create a gridded output with the guesses so far */
%macro reportStatus;
  data _null_;
    length background $ 50 message $ 40;
    array c[5]  $ 40 checked1-checked5;
    set status(obs=6) end=last;
    /* Credit for this approach goes to my SAS friends in Japan!                          */
    /*  http://sas-tumesas.blogspot.com/2022/03/wordlesasdo-overhash-iterator-object.html */
    dcl odsout ob ();
      ob.layout_gridded (columns: 5, rows: 1, column_gutter: '2mm');
      do i=1 to 5;
        if char(status,i) = 'G' then
          background = "green";
        else if char(status,i) = 'Y' then
          background = "darkyellow";
        else if char(status,i) = 'B' then
          background = "gray";
        text = cats ("color = white height = 1.5cm width = 1.5cm fontsize = 5 vjust = center background =", background);
        ob.region ();
        ob.table_start ();
          ob.row_start ();
            ob.format_cell (data: upcase(c[i]), style_attr: text);
          ob.row_end ();
        ob.table_end ();
        call missing (background);
      end;
    ob.layout_end ();

    if status='GGGGG' then do;
     if _n_ = 1 then message = "GENIUS!";
     if _n_ = 2 then message = "MAGNIFICENT!";
     if _n_ = 3 then message = "IMPRESSIVE!";
     if _n_ = 4 then message = "SPLENDID!";
     if _n_ = 5 then message = "GREAT!";
     if _n_ = 6 then message = "PHEW!";
    end;
    if last then do;
      if status ^= 'GGGGG' and _n_=6 then message="Missed it (%sysfunc(upcase(&gamepick)))!";
      message=catx(' ',message,"Guess",_n_,"of 6");
      call symputx('statmsg',message);
    end;
  run;

  proc odstext;
  p "&statmsg." 
   / style=[color=green font_size=4 just=c fontweight=bold];
  run;
%mend;

/* process a word guess */
%macro guess(guess);
  %let guess = %sysfunc(lowcase(&guess));
	/* Check to see if guess is valid */
	proc sql noprint;
		select count(word) into :is_valid 
			from allowed_words
				where word="&guess.";
	run;

	%if &is_valid. eq 0 %then
		%do; 
       proc odstext;
       p "%sysfunc(upcase(&guess.)) is not a valid guess." 
         / style=[color=blue just=c fontweight=bold];
       run;
			%put &guess. is not a valid guess.;
		%end;
	%else
		%do;
			data _status(keep=checked: status);
        /* checked array will output our guessed letters */
				array check{5}  $ 8 checked1-checked5;
        /* stat array will track guess status per position */
        /* will output to a status var at the end          */
				array stat{5} $ 1;
				length status $ 5;
        /* these arrays are solution word letters, guess letters */
				array word{5} $ 1;
				array guess{5} $ 1;

				do i = 1 to 5;
					word[i] = char("&gamepick.",i);
					guess[i] = char("&guess",i);
				end;

				/* Better check for any in the correct spot first */
				do i = 1 to 5;
					/* if the guess letter in this position matches */
					if guess[i]=word[i] then
						do;
							stat[i] = 'G';
							check[i]=guess[i];
							word[i]='0'; /* null out so we don't find again */
						end;
				end;

        /* Now check for right letter, wrong spot */
				do i=1 to 5;
          /* skip those we already determined are correct */
					if stat[i] ^= 'G' then
						do;
							c = whichc(guess[i], of word[*]);

							/* if the guess letter is in another position */
							if c>0 then
								do;
									check[i]=guess[i];
									stat[i] = 'Y';
                  /* if there was a letter found, null it out so we can't find again */
                  word[c]='0';
								end;
							/* else no match, whichc() returned 0 */
							else
								do;
									check[i]=guess[i];
									stat[i] = 'B';
								end;
						end;
				end;

        /* Save string of guess status */
				status = catt(of stat[*]);
			run;

      /* append to game status thus far */
			data status;
				set status _status;
			run;

      /* cleanup temp data */
			proc delete data=_status;
			run;

		%end;

  /* output the report of game so far */
	%reportStatus;
%mend;

/* 
 sample usage - start game and then guess 
 with your favorite start word

 %startGame;
 %guess(adieu);

 Then submit more guesses using the %guess macro until 
 you solve it...or run out of guesses.

*/




  