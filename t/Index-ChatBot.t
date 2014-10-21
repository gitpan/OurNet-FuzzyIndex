#!/usr/bin/perl -w

use strict;
use Test;

my @test;

BEGIN {
    @test = (
	'�Ѧ�L�`, �O�ͷ��k.'
	=> '��ڻ��o���O XX ��t�C���d�D�A�ڤ~�Q�����',

	'�ڷM�H���ߤ]�v!'     
	=> '�S������d�o��F�h���@�ˬK���C',

	'���F�פ��Ƥ�.',      
	=> '�p�G�A�������o�ڪ��k���A����A�]�N���ȱo�ڪ��I�q�C',

	# sort bug
	'�޼^�ǫ�, �����I��.',
	=> qr/^(?:\Q�o�د��k�Ӵd�s�F�C\E|\Q�O��ˤF�V�l��]���^�C\E)$/,
    );

    plan tests => 1 + (@test / 2);
}

use OurNet::ChatBot;

ok(my $db = OurNet::ChatBot->new('fianjmo', 'fianjmo.db', 1));

while (my($k, $v) = splice(@test, 0, 2)) {
    ok($db->input($k), $v);
}
